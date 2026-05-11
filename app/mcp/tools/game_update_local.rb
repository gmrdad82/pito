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
    # single-element array, and an explicit `null` clears every
    # ownership row. Both forms route through the same
    # `game_platform_ownerships` upsert path so the wire contract stays
    # consistent across the singular and plural callers.
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
            description: "Phase 27 §1a — array of Platform ids the user owns this game on. Null wipes every ownership row."
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

        # Phase 27 §1a — Platform-ownership input normalization.
        # Accept either the new plural array form or the legacy
        # singular id. Either form is normalized to a (possibly empty)
        # Array of integer ids; nil means "leave ownerships untouched"
        # (the keys aren't present), explicit-nil-as-value clears the
        # ownership set.
        ownership_input_present = input.key?(:platform_owned_ids) || input.key?(:platform_owned_id)
        ownership_ids =
          if input.key?(:platform_owned_ids)
            Array(input[:platform_owned_ids]).compact.map(&:to_i).uniq
          elsif input.key?(:platform_owned_id)
            singular = input[:platform_owned_id]
            singular.nil? ? [] : [ singular.to_i ]
          else
            nil
          end

        return error_response("no fields to update.") if attrs.empty? && !ownership_input_present

        if YesNo.from_yes_no(confirm) == false
          changes = attrs.transform_values { |new_v| { new: new_v } }
          changes[:platform_owned_ids] = { new: ownership_ids } if ownership_input_present
          payload = { preview: true, id: game.id, changes: changes,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
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
          payload = { id: game.id, message: "game updated.",
                      title: game.title,
                      platform_owned_ids: game.reload.owned_platforms.map(&:id) }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't update game: #{game.errors.full_messages.join(', ')}")
        end
      rescue ActiveRecord::RecordInvalid => e
        error_response("couldn't update game: #{e.record.errors.full_messages.join(', ')}")
      rescue ActiveRecord::RecordNotFound => e
        error_response("platform not found: #{e.message}")
      end

      # Phase 27 §1a — bring `game.game_platform_ownerships` into shape
      # with the supplied id list. Idempotent: existing rows for ids in
      # the list are preserved (so `acquired_at` / `store` / `notes`
      # metadata isn't wiped), rows for ids not in the list are
      # destroyed, ids missing a row get one created.
      def self.sync_ownerships!(game, platform_ids)
        platform_ids = platform_ids.compact.map(&:to_i).uniq
        existing = game.game_platform_ownerships.includes(:platform).to_a

        # Validate platform existence up front so a single bad id
        # surfaces as a clear error rather than a partial commit.
        if platform_ids.any?
          found_ids = Platform.where(id: platform_ids).pluck(:id)
          missing = platform_ids - found_ids
          if missing.any?
            raise ActiveRecord::RecordNotFound, "unknown platform_id(s): #{missing.join(', ')}"
          end
        end

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
