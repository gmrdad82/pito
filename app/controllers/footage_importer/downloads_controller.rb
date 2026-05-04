# Phase 4 §8 — unified `pito` CLI binary download endpoint.
#
# Single controller, branches on Rails.env:
#   - production → §8.3: GitHub Releases API + asset stream with PAT auth
#     (gmrdad82/pito is private). Filter `tag_name =~ ^pito-`, pick most
#     recent, fetch the asset by API URL (NOT browser_download_url — only the
#     API URL accepts PAT auth on private repos).
#   - non-production → §8.2: read the local cargo-built binary from
#     `extras/cli/target/release/pito`. 503 if the file isn't there yet.
#
# Both paths stream as `application/octet-stream` with the canonical
# `Content-Disposition: attachment; filename="pito"`. The `pito-<sha>` tag
# shape lives only in the GitHub Release tag and in `pito version` output.
module FootageImporter
  class DownloadsController < ApplicationController
    DEV_BINARY_PATH = Rails.root.join("extras", "cli", "target", "release", "pito").freeze
    GITHUB_RELEASES_URL = "https://api.github.com/repos/gmrdad82/pito/releases".freeze
    PITO_TAG_PREFIX = "pito-".freeze

    def show
      if Rails.env.production?
        serve_from_github_release
      else
        serve_local_binary
      end
    end

    private

    def serve_local_binary
      unless File.exist?(DEV_BINARY_PATH)
        render json: {
          error: "pito_cli_unbuilt",
          message: "cargo build hasn't finished yet — try again in a moment"
        }, status: :service_unavailable
        return
      end

      send_file DEV_BINARY_PATH,
                filename: "pito",
                type: "application/octet-stream",
                disposition: "attachment"
    end

    def serve_from_github_release
      releases = fetch_releases
      release = pick_latest_pito_release(releases)
      unless release
        render json: { error: "no_pito_release" }, status: :not_found
        return
      end

      asset = pick_pito_asset(release)
      unless asset
        render json: { error: "no_pito_asset" }, status: :not_found
        return
      end

      stream_asset(asset.fetch("url"))
    end

    def fetch_releases
      uri = URI.parse(GITHUB_RELEASES_URL)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{github_token}"
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "pito-rails"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      return [] unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end

    def pick_latest_pito_release(releases)
      releases
        .select { |r| r["tag_name"].to_s.start_with?(PITO_TAG_PREFIX) }
        .max_by { |r| r["created_at"].to_s }
    end

    def pick_pito_asset(release)
      Array(release["assets"]).find { |a| a["name"] == "pito" }
    end

    def stream_asset(api_url)
      response = http_get_following_redirects(api_url)
      unless response.is_a?(Net::HTTPSuccess)
        render json: { error: "github_asset_fetch_failed", status: response&.code }, status: :bad_gateway
        return
      end

      send_data response.body,
                filename: "pito",
                type: "application/octet-stream",
                disposition: "attachment"
    end

    def http_get_following_redirects(url, depth: 0)
      return nil if depth > 5

      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{github_token}"
      request["Accept"] = "application/octet-stream"
      request["User-Agent"] = "pito-rails"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      if response.is_a?(Net::HTTPRedirection)
        http_get_following_redirects(response["Location"], depth: depth + 1)
      else
        response
      end
    end

    def github_token
      Rails.application.credentials.dig(:github, Rails.env.to_sym, :token)
    end
  end
end
