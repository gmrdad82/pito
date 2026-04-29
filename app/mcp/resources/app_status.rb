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
          connected_channels: Channel.connected.count,
          videos: Video.count,
          video_stats_entries: VideoStat.count,
          saved_views: SavedView.count,
          search_healthy: search_healthy,
          search_stats: search_stats,
          settings: {
            max_panes: AppSetting.get("max_panes") || "(default: 3)",
            pane_title_length: AppSetting.get("pane_title_length") || "(default: 14)",
            theme: AppSetting.get("theme") || "auto"
          }
        }

        [ { uri: uri, mimeType: "application/json", text: JSON.pretty_generate(data) } ]
      rescue => e
        [ { uri: uri, mimeType: "text/plain", text: "error reading status: #{e.message}" } ]
      end
    end
  end
end
