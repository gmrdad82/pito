# Phase 27 v2 spec 07 — download platform-logo favicons.
#
# One-shot Rake task that fetches each canonical platform's favicon
# from Google's favicon service (`https://www.google.com/s2/favicons`)
# at TWO sizes (16 px for tile footers, 64 px for the detail page)
# and saves the raw PNG bytes to `public/platform_logos/`.
#
# The web app reads from the static files — no runtime network calls,
# no asset-pipeline digesting. Re-run this task to refresh logos when
# a brand updates its favicon. Idempotent: existing files are
# overwritten with fresh downloads.
#
# Usage:
#
#   bin/rails pito:platform_logos:download
#
# Failure handling: HTTP non-200 logs a warning and continues with the
# next platform / size; the task always exits 0 so a flaky single
# fetch does not block the other 9 downloads. Re-run after fixing the
# offending fetch.

require "net/http"
require "uri"
require "fileutils"

namespace :pito do
  namespace :platform_logos do
    # Canonical 5-platform mapping. Order is the project's
    # display order — also the order `KNOWN_LOGOS` reuses in
    # `PlatformLogosHelper` (PS5 wins over Switch2 over Steam etc.
    # when a game touches multiple).
    PLATFORM_LOGO_SOURCES = [
      { slug: "ps5",     domain: "playstation.com" },
      { slug: "switch2", domain: "nintendo.com" },
      { slug: "steam",   domain: "steampowered.com" },
      { slug: "gog",     domain: "gog.com" },
      { slug: "epic",    domain: "epicgames.com" }
    ].freeze

    PLATFORM_LOGO_SIZES = [ 16, 64 ].freeze

    desc "Download platform-logo favicons to public/platform_logos/"
    task download: :environment do
      target_dir = Rails.public_path.join("platform_logos")
      FileUtils.mkdir_p(target_dir)

      PLATFORM_LOGO_SOURCES.each do |source|
        PLATFORM_LOGO_SIZES.each do |size|
          url  = "https://www.google.com/s2/favicons?domain=#{source[:domain]}&sz=#{size}"
          dest = target_dir.join("#{source[:slug]}-#{size}.png")

          begin
            response = fetch_logo(url)
            if response.is_a?(Net::HTTPSuccess)
              File.binwrite(dest, response.body)
              puts "[pito:platform_logos] saved public/platform_logos/" \
                   "#{source[:slug]}-#{size}.png (#{response.body.bytesize} bytes)"
            else
              warn "[pito:platform_logos] WARN: #{source[:slug]} #{size} " \
                   "fetch returned HTTP #{response.code}; skipped."
            end
          rescue StandardError => e
            warn "[pito:platform_logos] WARN: #{source[:slug]} #{size} " \
                 "fetch raised #{e.class}: #{e.message}; skipped."
          end
        end
      end
    end

    # Issue the GET via Net::HTTP. Follows up to 3 redirects (Google's
    # favicon service occasionally 302s through a CDN before serving
    # the PNG bytes). Plain `Net::HTTP.get_response` does NOT follow
    # redirects on its own.
    def fetch_logo(url, redirects_remaining: 3)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.open_timeout = 5
        http.read_timeout = 10
        http.get(uri.request_uri)
      end

      if response.is_a?(Net::HTTPRedirection) && redirects_remaining.positive?
        location = response["location"]
        next_url = location.start_with?("http") ? location : URI.join(url, location).to_s
        fetch_logo(next_url, redirects_remaining: redirects_remaining - 1)
      else
        response
      end
    end
  end
end
