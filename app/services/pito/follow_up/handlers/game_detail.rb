# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-detail events (reply_target: "game_detail").
      #
      # The detail message is stamped `reply_target: "game_detail"` by
      # `Pito::Game::DetailMessage.call`. The user can reply:
      #
      #   #<handle> rm / delete
      #     → Emit a confirmation event (`command: "game_delete"`) using the
      #       existing executor branch that already destroys the Game row.
      #       Mode: :append — the confirmation lands as a new event below the card.
      #
      #   #<handle> resync
      #     → Emit a confirmation event (`command: "game_resync"`) whose executor
      #       branch enqueues `GameIgdbSync`. The card stays follow-up-able.
      #
      #   #<handle> update ownership <platforms>
      #     → Parse platform tokens (shared PLATFORM_SYNONYMS map), apply
      #       GamePlatformOwnership writes/destroys, then MUTATE the detail
      #       message via `Pito::Game::DetailMessage.call` so the owned-platforms
      #       row reflects the change. Retains `reply_handle` + `reply_target`
      #       so the card stays repliable (chainable, not consumed).
      #
      #   #<handle> link to video <id|title>
      #     → Resolve the video (id `#N`/`N` or title ILIKE),
      #       `VideoGameLink.find_or_create_by!`, append a witty ack.
      #
      # == Mode
      #
      # The base mode is `:append` (rm/resync/link produce new events).
      # The `update ownership` action returns `Result::Mutation` directly — the
      # handler switches return type for that specific action even though the
      # declared mode is :append.  The dispatch job inspects the result type to
      # determine whether to mutate or append.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model.
      class GameDetail < Pito::FollowUp::Handler
        self.target "game_detail"
        self.mode   :append
        self.actions "rm", "resync", "owned", "link"

        # Maps user-supplied synonyms to canonical platform tokens.
        # Shared constants from Pito::Chat::Handlers::Update — if extracted to a
        # shared service later, point here.
        PLATFORM_SYNONYMS = {
          "ps"          => "ps",
          "ps4"         => "ps",
          "ps5"         => "ps",
          "playstation" => "ps",
          "sony"        => "ps",
          "switch"      => "switch",
          "switch1"     => "switch",
          "switch2"     => "switch",
          "nintendo"    => "switch",
          "steam"       => "steam",
          "gog"         => "steam",
          "epic"        => "steam",
          "pc"          => "steam"
        }.freeze

        # @param event        [Event]        the game-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Mutation | Result::Error]
        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          case action
          when "rm", "delete"
            handle_delete(event, conversation)
          when "resync"
            handle_resync(event, conversation)
          when "update"
            handle_update(event, args, conversation)
          when "link"
            handle_link(event, args, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── rm / delete ────────────────────────────────────────────────────────

        def handle_delete(event, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          payload = {
            command:    "game_delete",
            body:       Pito::Copy.render("pito.copy.games.delete_confirm", { title: game.title }),
            html:       false,
            game_id:    game.id,
            game_title: game.title
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── resync ─────────────────────────────────────────────────────────────

        def handle_resync(event, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          payload = {
            command:    "game_resync",
            body:       Pito::Copy.render("pito.copy.games.resync_confirm", { title: game.title }),
            html:       false,
            game_id:    game.id,
            game_title: game.title
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── update ownership <platforms> ───────────────────────────────────────

        def handle_update(event, args, conversation)
          # Drop the literal word "ownership" if present; also drop "game"/"games"
          words = args.to_s.strip.split
          words = words.reject { |w| %w[ownership game games].include?(w.downcase) }

          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          tokens = parse_platforms(words)
          if tokens.empty?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_platforms",
              message_args: {}
            )
          end

          apply_ownership(game, tokens)

          # Re-render the detail message with the same handle + target so the card
          # remains follow-up-able (chainable, not consumed).
          original_handle = event.payload["reply_handle"].to_s
          new_payload = Pito::Game::DetailMessage.call(game.reload, conversation:)
          # Override the freshly generated handle with the original so Turbo replace
          # finds the correct DOM element (event id stays the same; handle must match).
          new_payload["reply_handle"] = original_handle
          new_payload["reply_target"] = "game_detail"
          # reply_consumed NOT set — stays repliable.

          Pito::FollowUp::Result::Mutation.new(
            kind:    "system",
            payload: new_payload
          )
        end

        # ── link to video <id|title> ───────────────────────────────────────────

        def handle_link(event, args, conversation)
          # Drop the word "to" and "video"/"videos"
          words = args.to_s.strip.split
          words = words.drop(1) if words.first&.downcase == "to"
          words = words.drop(1) if %w[video videos].include?(words.first&.downcase)
          ref   = words.join(" ").strip

          if ref.blank?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_video_ref",
              message_args: {}
            )
          end

          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          video = resolve_video(ref)
          if video.nil?
            return Pito::FollowUp::Result::Append.new(
              events: [
                {
                  kind:    "system",
                  payload: { text: Pito::Copy.render("pito.copy.videos.not_found", { ref: ref }) }
                }
              ]
            )
          end

          VideoGameLink.find_or_create_by!(video: video, game: game)

          text = Pito::Copy.render("pito.copy.games.linked", { game: game.title, video: video.title })
          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "system", payload: { text: text } } ]
          )
        end

        # ── helpers ────────────────────────────────────────────────────────────

        # Resolve the game from the event payload.
        # DetailMessage stamps `game_id` into the payload (added in P12).
        def resolve_game_from_event(event)
          payload = event.payload.with_indifferent_access
          game_id = payload[:game_id]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end

        def resolve_video(ref)
          id = ref.delete_prefix("#")
          if id.match?(/\A\d+\z/)
            ::Video.find_by(id: id)
          else
            ::Video.find_by("title ILIKE ?", ref)
          end
        end

        # Tolerant platform parser (mirrors Pito::Chat::Handlers::Update).
        def parse_platforms(words)
          raw = words.join(" ")
          raw.split(/[,.*\s]+/)
             .map { |tok| PLATFORM_SYNONYMS[tok.downcase] }
             .compact
             .uniq
        end

        def apply_ownership(game, wanted_tokens)
          existing = game.game_platform_ownerships.pluck(:platform_token)
          to_add    = wanted_tokens - existing
          to_remove = existing - wanted_tokens

          to_add.each    { |tok| game.game_platform_ownerships.create!(platform_token: tok) }
          to_remove.each { |tok| game.game_platform_ownerships.where(platform_token: tok).destroy_all }
        end

        def game_not_found_error
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.game_enhanced.errors.game_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
