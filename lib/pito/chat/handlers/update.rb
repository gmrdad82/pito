# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `update` chat tool — the ONE typed surface for entity
      # metadata writes (the AI suggests these commands; only the owner runs
      # them):
      #
      #   update game footage <id> <hours>      — local write (0.5-step ceil)
      #   update game price <id> <amount>       — local write (euro, 2dp)
      #   update game platform <id> <name>      — local write (adds the family)
      #   update vid description <id> <text>    — confirmation → YouTube push
      #   update vid tags <id> <t1, t2, …>      — confirmation → YouTube push
      #
      # Game fields reuse the same canonical parsers and success copy the
      # retired setter tools used (Pito::Games::{FootageAmount,PriceAmount,
      # PlatformInput}). Vid fields never write directly: they stage a
      # :confirmation event (MessageBuilder::Video::MetadataConfirmation) whose
      # `yes` runs Confirmation::Executor#confirm_video_metadata — local column
      # + a field-restricted VideosClient PUT via VideoRemoteStatusSync.
      #
      # == Mass form (WP4): `update <noun> <field> <id> <v>, <id> <v>, …`
      #
      # PATTERN now captures the whole tail (`id + value…`) as ONE group — the
      # id is no longer pulled out at the top level — so MASS_SPLIT can run on
      # it. MASS_SPLIT opens a new row at a comma ONLY when it's immediately
      # followed by `<id> <value>` (an id token, whitespace, then more
      # content); a comma that ISN'T followed by that shape (a plain
      # comma-separated tags list, or a trailing bare number with nothing
      # after it) never splits. One group → the pre-WP4 single path, byte
      # identical (the group is parsed the exact same way the old PATTERN's
      # `#?(\d+)\s+(.+)` captured it). ≥2 groups → mass:
      #
      #   - game fields (footage/price/platform) apply PER ROW and never
      #     abort on a bad row — one plain-text :system report names every
      #     row's outcome (Pito::MessageBuilder::Game::MassUpdateSummary).
      #   - vid fields (description/tags) never write directly: every row
      #     that resolves stages into ONE "video_metadata_mass" confirmation
      #     card; rows that don't resolve are named as skipped in its
      #     expand_detail but never block the rows that did. Zero valid rows
      #     → a plain error, no card at all.
      class Update < Pito::Chat::Handler
        self.tool = :update
        self.description_key = "pito.chat.update.descriptions.update"

        GAME_FIELDS = %w[footage price platform].freeze
        VID_FIELDS  = %w[description tags].freeze
        NOUNS = {
          "game" => "game", "games" => "game",
          "vid" => "vid", "vids" => "vid", "video" => "vid", "videos" => "vid"
        }.freeze

        # "update <noun> <field> <id + value…>" — the tail is everything after
        # the field, RAW; MASS_SPLIT/ROW_PATTERN below carve it into rows.
        PATTERN = /\Aupdate\s+(\S+)\s+(\S+)\s+(.+)\z/im
        # One row: a leading #?<id>, whitespace, then the rest as the value.
        ROW_PATTERN = /\A#?(\d+)\s+(.+)\z/m
        # A comma opens a new row only when what follows it (after optional
        # whitespace) is itself the START of a row — #?<id> then whitespace
        # then at least one more non-whitespace char. A bare trailing number
        # with nothing after it (the WP4 escape hatch: `5 60 fps, 2023`) does
        # NOT match — the comma stays inside that one row's value.
        MASS_SPLIT = /,\s*(?=#?\d+\s+\S)/

        BAD_ROW_REASON = "couldn't find an id and a value there"
        NOT_FOUND_REASON = "not found"
        NO_VALUE_REASON = "no value given"

        def call
          m = message.raw.to_s.strip.match(PATTERN)
          return usage unless m

          noun  = NOUNS[m[1].downcase]
          field = m[2].downcase
          return usage unless noun && valid_field?(noun, field)

          groups = m[3].strip.split(MASS_SPLIT)
          return mass_update(noun, field, groups) if groups.size > 1

          row = groups.first.match(ROW_PATTERN)
          return usage unless row

          id, value = row[1], row[2].strip
          noun == "game" ? update_game(field, id, value) : update_vid(field, id, value)
        end

        private

        def valid_field?(noun, field)
          noun == "game" ? GAME_FIELDS.include?(field) : VID_FIELDS.include?(field)
        end

        # ── game fields (local writes, immediate) ──────────────────────────────

        def update_game(field, id, value)
          return usage unless GAME_FIELDS.include?(field)

          game = ::Game.find_by(id: id)
          return not_found("game ##{id}") unless game

          case field
          when "footage"  then update_footage(game, value)
          when "price"    then update_price(game, value)
          when "platform" then update_platform(game, value)
          end
        end

        def update_footage(game, value)
          hours = Pito::Games::FootageAmount.parse(value.split(/\s+/).first)
          return bad_value("footage", value) if hours.nil?

          game.update!(footage_hours: hours)
          ok_text("pito.copy.footage.updated", game: game.title, hours: format("%gh", hours.to_f))
        end

        def update_price(game, value)
          amount = Pito::Games::PriceAmount.parse(value.split(/\s+/).first)
          return bad_value("price", value) if amount.nil?

          game.update!(price: amount)
          body = Pito::Copy.render_html(
            "pito.copy.price.updated",
            { game: game.title, price: Pito::Games::PriceGlyphs.html(game.price) },
            shimmer: [ :game ]
          )
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { "body" => body.to_s, "html" => true } }
          ])
        end

        def update_platform(game, value)
          # normalize titleizes free text deliberately (lenient platform entry,
          # same as the retired setter) — only a BLANK value is refused.
          normalized = Pito::Games::PlatformInput.normalize(value)
          return bad_value("platform", value) if normalized.blank?

          unless game.platforms.include?(normalized)
            game.update!(platforms: game.platforms + [ normalized ])
            GameEmbedIndexJob.perform_later(game.id)
          end
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system,
              payload: Pito::MessageBuilder::Game::PlatformSet.call(game, platform: normalized, removed: false) }
          ])
        end

        # ── vid fields (staged; the confirmation executes) ─────────────────────

        def update_vid(field, id, value)
          return usage unless VID_FIELDS.include?(field)

          video = ::Video.find_by(id: id)
          return not_found("vid ##{id}") unless video

          staged = field == "tags" ? value.split(",").map(&:strip).reject(&:blank?) : value
          return bad_value(field, value) if staged.blank?

          payload = Pito::MessageBuilder::Video::MetadataConfirmation.call(
            video, field:, value: staged, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: } ])
        end

        # ── mass form (WP4) ─────────────────────────────────────────────────────

        def mass_update(noun, field, groups)
          noun == "game" ? mass_update_game(field, groups) : mass_update_vid(field, groups)
        end

        # Game fields apply PER ROW — a bad row (unparseable, unresolved id, or
        # a value the field parser rejects) is collected and reported, never
        # aborts the rows around it. Rows that share a game/field still coalesce
        # into whatever the LAST valid row sets (last-write-wins), same as
        # running the single-row form N times in sequence.
        def mass_update_game(field, groups)
          rows    = groups.map { |text| game_row(field, text) }
          payload = Pito::MessageBuilder::Game::MassUpdateSummary.call(field:, rows:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # One typed row → an applied or skipped row hash for MassUpdateSummary.
        # Never raises/returns an Error — every outcome folds into a row.
        def game_row(field, text)
          match = text.match(ROW_PATTERN)
          return skipped_row(ref_for(nil, text), BAD_ROW_REASON) unless match

          id, value = match[1], match[2].strip
          ref  = ref_for(id, text)
          game = ::Game.find_by(id: id)
          return skipped_row(ref, NOT_FOUND_REASON) unless game

          display = apply_game_field(field, game, value)
          return skipped_row(ref, bad_value_reason(field, value)) if display.nil?

          applied_row(ref, game.title, display)
        end

        # Mutates +game+ and returns the applied value's DISPLAY string, or nil
        # when the field parser rejects +value+. Reuses the exact same pure
        # parsers the single-row update_footage/update_price/update_platform
        # methods call — only the "what to return" step differs (a display
        # string here, a Result::Ok event there).
        def apply_game_field(field, game, value)
          case field
          when "footage"  then apply_footage_field(game, value)
          when "price"    then apply_price_field(game, value)
          when "platform" then apply_platform_field(game, value)
          end
        end

        def apply_footage_field(game, value)
          hours = Pito::Games::FootageAmount.parse(value.split(/\s+/).first)
          return nil if hours.nil?

          game.update!(footage_hours: hours)
          format("%gh", hours.to_f)
        end

        def apply_price_field(game, value)
          amount = Pito::Games::PriceAmount.parse(value.split(/\s+/).first)
          return nil if amount.nil?

          game.update!(price: amount)
          Pito::Formatter::Price.call(game.price)
        end

        def apply_platform_field(game, value)
          normalized = Pito::Games::PlatformInput.normalize(value)
          return nil if normalized.blank?

          unless game.platforms.include?(normalized)
            game.update!(platforms: game.platforms + [ normalized ])
            GameEmbedIndexJob.perform_later(game.id)
          end
          normalized
        end

        # Vid fields never write directly: every row that resolves (a real vid
        # + a non-blank staged value) stages into ONE "video_metadata_mass"
        # confirmation card; rows that don't resolve are named as skipped in
        # its expand_detail but never block the rows that did. Zero valid rows
        # → a plain error, no card at all (nothing to confirm).
        def mass_update_vid(field, groups)
          rows  = groups.map { |text| vid_row(field, text) }
          valid = rows.select { |row| row[:applied] }
          return mass_vid_empty unless valid.any?

          payload = mass_metadata_confirmation(field, rows, valid)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: } ])
        end

        # One typed row → an applied (staged) or skipped row hash. Never raises
        # — every outcome folds into a row, mirroring game_row.
        def vid_row(field, text)
          match = text.match(ROW_PATTERN)
          return skipped_row(ref_for(nil, text), BAD_ROW_REASON) unless match

          id, value = match[1], match[2].strip
          ref   = ref_for(id, text)
          video = ::Video.find_by(id: id)
          return skipped_row(ref, NOT_FOUND_REASON) unless video

          staged = field == "tags" ? value.split(",").map(&:strip).reject(&:blank?) : value
          return skipped_row(ref, NO_VALUE_REASON) if staged.blank?

          { applied: true, ref:, video:, staged: }
        end

        def mass_metadata_confirmation(field, rows, valid)
          payload = {
            "command" => "video_metadata_mass",
            "field"   => field,
            "body"    => Pito::Copy.render("pito.copy.update.mass_metadata_confirm",
                                            { count: valid.size, field: field }),
            "html"          => false,
            "items"         => valid.map { |row| mass_metadata_item(row) },
            "expand_detail" => rows.map { |row| mass_metadata_row_line(row) }
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end

        def mass_metadata_item(row)
          { "video_id" => row[:video].id, "video_title" => row[:video].title, "staged_value" => row[:staged] }
        end

        def mass_metadata_row_line(row)
          if row[:applied]
            Pito::Copy.render("pito.copy.update.mass_row_applied", {
              ref: row[:ref], title: row[:video].title,
              value: Pito::MessageBuilder::Video::MetadataConfirmation.preview(row[:staged])
            })
          else
            Pito::Copy.render("pito.copy.update.mass_metadata_row_skipped",
                               { ref: row[:ref], reason: row[:reason] })
          end
        end

        def mass_vid_empty
          Pito::Chat::Result::Error.new(message_key: "pito.chat.update.mass_no_valid_rows", message_args: {})
        end

        # "#<id>" when the row parsed an id; the quoted raw segment otherwise
        # (mirrors Pito::Chat::Handlers::Schedule's bad-segment quoting) — the
        # only row shape with nothing to point a "#id" at.
        def ref_for(id, segment)
          id ? "##{id}" : "'#{segment}'"
        end

        def applied_row(ref, title, value)
          { applied: true, ref:, title:, value: }
        end

        def skipped_row(ref, reason)
          { applied: false, ref:, reason: }
        end

        def bad_value_reason(field, value)
          "couldn't read '#{value}' as a #{field} value"
        end

        # ── replies ────────────────────────────────────────────────────────────

        def usage
          Pito::Chat::Result::Error.new(message_key: "pito.chat.update.usage", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.update.not_found", message_args: { ref: }
          )
        end

        def bad_value(field, value)
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.update.bad_value", message_args: { field:, value: }
          )
        end

        def ok_text(key, **args)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(key, **args) }
          ])
        end
      end
    end
  end
end
