module Mcp
  module Tools
    # Phase 14 §3 — seed a Bundle's membership from IGDB. Mirrors the
    # web `seed_from_igdb` controller action: fetches IGDB-side games
    # for the bundle's `igdb_source_type` / `igdb_source_id` pair,
    # creates any missing local Game rows (and enqueues
    # `GameIgdbSync` for them), then adds non-member games to the
    # bundle. Additive only — never removes existing members.
    class BundleSeedFromIgdb < MCP::Tool
      tool_name "bundle_seed_from_igdb"
      description "Seed a non-custom bundle's membership from IGDB. Additive only."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Bundle id" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        bundle = Bundle.find_by(id: id)
        return error_response("bundle not found: #{id}") unless bundle
        if bundle.type_custom? || bundle.igdb_source_type.blank? || bundle.igdb_source_id.blank?
          return error_response("bundle has no IGDB source configured (custom bundles cannot be seeded).")
        end

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, id: bundle.id, name: bundle.name,
                      igdb_source_type: bundle.igdb_source_type,
                      igdb_source_id: bundle.igdb_source_id,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        client = Igdb::Client.new
        igdb_games =
          case bundle.igdb_source_type
          when "franchise"        then client.fetch_games_for_franchise(bundle.igdb_source_id.to_i)
          when "source_collection" then client.fetch_games_for_collection(bundle.igdb_source_id.to_i)
          when "source_genre"      then client.fetch_games_for_genre(bundle.igdb_source_id.to_i)
          else []
          end

        added = 0
        Array(igdb_games).each do |g|
          igdb_id = g["id"].to_i
          next unless igdb_id.positive?

          game = Game.find_by(igdb_id: igdb_id)
          if game.nil?
            game = Game.new(igdb_id: igdb_id, title: g["name"].presence || "Untitled game")
            next unless game.save
            GameIgdbSync.perform_async(game.id)
          end

          next if bundle.bundle_members.exists?(game_id: game.id)
          bundle.bundle_members.create!(game_id: game.id)
          added += 1
        end
        bundle.update_columns(last_error: nil, updated_at: Time.current)

        payload = { id: bundle.id, added: added, message: "seeded #{added} member#{'s' if added != 1}." }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      rescue Igdb::Client::Error => e
        bundle&.update_columns(last_error: "seed: #{e.message}", updated_at: Time.current)
        error_response("igdb error: #{e.message}")
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
