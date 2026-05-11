module Mcp
  module Tools
    # Phase 14 §3 / Phase 27 §1a — update local-only Game fields. IGDB-
    # sourced columns are NOT writable through this tool (use
    # `game_resync` to re-pull).
    #
    # Per-platform ownership is multi-valued from Phase 27 §1a onward:
    # the canonical input is `platform_owned_ids` (an integer array of
    # Platform ids). The legacy singular form `platform_owned_id` is
    # accepted for back-compat — a scalar value is auto-wrapped into a
    # single-element array, and explicit `null` is treated as "skip"
    # (no ownership change) to match legacy callers that use null for
    # "leave untouched". To un-own everywhere with the plural form, send
    # an empty array. When both forms are supplied, plural wins and a
    # `warning` field is emitted in the response. Unknown platform ids
    # are dropped with a warning rather than 422'd. Both forms route
    # through the same `game_platform_ownerships` upsert path so the
    # wire contract stays consistent across singular and plural callers.
    class GameUpdateLocal < MCP::Tool
      tool_name "game_update_local"
      description "Update local-only game fields (platform_owned_ids, played_at, notes, hours_of_footage_manual)."

      # Phase 20 — friendly URLs. `id` accepts slug or integer-id string.
      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Game slug (igdb_slug) or integer id (as string)" },
          platform_owned_ids: {
            type: [ "array", "null" ],
            items: { type: "integer" },
            description: "Phase 27 §1a — array of Platform ids the user owns this game on. An empty array un-owns the game on every platform; absent leaves ownership untouched."
          },
          platform_owned_id: {
            type: [ "integer", "null" ],
            description: "DEPRECATED — singular form auto-wrapped to a single-element array. Prefer `platform_owned_ids`."
          },
          played_at: { type: [ "string", "null" ], description: "ISO date (YYYY-MM-DD) or null." },
          notes: { type: [ "string", "null" ] },
          hours_of_footage_manual: { type: [ "integer", "null" ] },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, confirm: "no", **input)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        game = begin
          Game.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("game not found: #{id}") unless game

        attrs = {}
        attrs[:played_at]               = input[:played_at]               if input.key?(:played_at)
        attrs[:notes]                   = input[:notes]                   if input.key?(:notes)
        attrs[:hours_of_footage_manual] = input[:hours_of_footage_manual] if input.key?(:hours_of_footage_manual)

        # Phase 27 §1a / §01g — Platform-ownership input normalization.
        # Accept either the new plural array form or the legacy singular
        # id. Either form is normalized to a (possibly empty) Array of
        # integer ids; key-absent means "leave ownerships untouched",
        # an explicit `null` singular value clears nothing (no-op),
        # and an explicit empty plural array un-owns the game on every
        # platform. When BOTH singular and plural are supplied the
        # plural form wins and a `warning` field is surfaced in the
        # response so legacy callers see the conflict. Unknown platform
        # ids are dropped (not 422'd) with a warning, matching the
        # spec's "graceful drop" rule.
        warnings = []
        plural_present   = input.key?(:platform_owned_ids)
        singular_present = input.key?(:platform_owned_id)
        # §01g — `platform_owned_id: null` is "skip" (no-op) per the
        # spec's back-compat note for legacy callers that send `null`
        # to mean "don't touch ownership". The plural form has the
        # opposite convention: an empty array un-owns everywhere.
        singular_is_noop = singular_present && input[:platform_owned_id].nil?
        ownership_input_present =
          plural_present || (singular_present && !singular_is_noop)

        ownership_ids =
          if plural_present && singular_present && !singular_is_noop
            warnings << "both `platform_owned_id` and `platform_owned_ids` supplied; plural wins."
            Array(input[:platform_owned_ids]).compact.map(&:to_i).uniq
          elsif plural_present
            Array(input[:platform_owned_ids]).compact.map(&:to_i).uniq
          elsif singular_present && !singular_is_noop
            [ input[:platform_owned_id].to_i ]
          else
            nil
          end

        return error_response("no fields to update.") if attrs.empty? && !ownership_input_present

        # Phase 27 §01g — drop unknown platform ids with a warning rather
        # than 422'ing the whole call. Mirrors the spec's "unknown id is
        # not a hard error" contract.
        if ownership_input_present && ownership_ids.any?
          found_ids = Platform.where(id: ownership_ids).pluck(:id)
          missing   = ownership_ids - found_ids
          if missing.any?
            warnings << "unknown platform_id(s) dropped: #{missing.sort.join(', ')}."
            ownership_ids = found_ids
          end
        end

        if YesNo.from_yes_no(confirm) == false
          changes = attrs.transform_values { |new_v| { new: new_v } }
          changes[:platform_owned_ids] = { new: ownership_ids } if ownership_input_present
          payload = { preview: true, id: game.id, changes: changes,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          payload[:warning] = warnings.join(" ") if warnings.any?
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        result = Game.transaction do
          game.update!(attrs) if attrs.any?
          if ownership_input_present
            sync_ownerships!(game, ownership_ids)
          end
          true
        end

        if result
          final_ids = game.reload.owned_platforms.map(&:id)
          payload = { id: game.id, message: "game updated.",
                      title: game.title,
                      platform_owned_ids: final_ids,
                      # Phase 27 §01g — back-compat scalar — first element
                      # of the plural set. Removed next phase per the
                      # one-phase deprecation window agreed in the spec.
                      platform_owned_id: final_ids.first }
          payload[:warning] = warnings.join(" ") if warnings.any?
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't update game: #{game.errors.full_messages.join(', ')}")
        end
      rescue ActiveRecord::RecordInvalid => e
        error_response("couldn't update game: #{e.record.errors.full_messages.join(', ')}")
      end

      # Phase 27 §1a — bring `game.game_platform_ownerships` into shape
      # with the supplied id list. Idempotent: existing rows for ids in
      # the list are preserved (so `acquired_at` / `store` / `notes`
      # metadata isn't wiped), rows for ids not in the list are
      # destroyed, ids missing a row get one created.
      #
      # Phase 27 §01g — the caller pre-validates platform existence and
      # drops unknown ids with a warning; this method trusts its input.
      def self.sync_ownerships!(game, platform_ids)
        platform_ids = platform_ids.compact.map(&:to_i).uniq
        existing = game.game_platform_ownerships.includes(:platform).to_a

        existing.each do |row|
          row.destroy! unless platform_ids.include?(row.platform_id)
        end

        new_ids = platform_ids - existing.map(&:platform_id)
        new_ids.each do |pid|
          game.game_platform_ownerships.create!(platform_id: pid)
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
