module Mcp
  module Resources
    module AppStatus
      URI_PREFIX = "pito://status"

      def self.definitions
        [
          MCP::Resource.new(
            uri: URI_PREFIX,
            name: "app status",
            description: "Current pito state — channel count, video count, search health, settings",
            mime_type: "application/json"
          )
        ]
      end

      def self.handles?(uri)
        uri == URI_PREFIX
      end

      def self.read(uri)
        search_healthy = begin
          Search.engine.healthy?
        rescue
          false
        end

        search_stats = begin
          Search.engine.index_stats
        rescue
          {}
        end

        data = {
          version: File.read(Rails.root.join("VERSION")).strip,
          channels: Channel.count,
          videos: Video.count,
          video_stats_entries: VideoStat.count,
          saved_views: SavedView.count,
          search_healthy: YesNo.to_yes_no(search_healthy),
          search_stats: search_stats,
          # Phase 29 (settings refactor) — workspace knobs come from
          # `config/pito.yml` via `Rails.application.config.x.pito.*`;
          # theme is browser-local (no server-side value) so it's
          # reported as a constant `"auto"` placeholder for callers
          # that still ship the field.
          settings: {
            max_panes: Rails.application.config.x.pito.max_panes,
            pane_title_length: Rails.application.config.x.pito.pane_title_length,
            theme: "auto"
          }
        }

        [ { uri: uri, mimeType: "application/json", text: JSON.pretty_generate(data) } ]
      rescue => e
        [ { uri: uri, mimeType: "text/plain", text: "error reading status: #{e.message}" } ]
      end
    end
  end
end
