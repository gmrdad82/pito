# Phase 27 v2 spec 07 — sourced platform-logo generator.
#
# One-shot Rake task that fetches each canonical platform's brand
# logo from the simpleicons.org CDN (monochrome black variant) and
# resizes it locally to two target sizes (16 px for tile footers,
# 64 px for the detail page). The downsized PNGs land in
# `public/platform_logos/` for the static asset path.
#
# The web app reads from the static files — no runtime network
# calls, no asset-pipeline digesting. Re-run this task to refresh
# logos when a brand updates its asset. Idempotent: every successful
# fetch first removes the existing 16/64 pair and rewrites both.
#
# Why monochrome black (per-platform source choice): the user picked
# the `/000000` color suffix (simpleicons) or `?color=%23000000`
# query (iconify) that pins the SVG fill to solid black (`#000000`).
# That gives a consistent, brand-correct, monochrome silhouette
# across PS5, Switch 2, Steam, GoG, and Epic — no
# corporate-bumper-vs-product-logo ambiguity, no per-CDN UA games,
# no Wikimedia fallback chain.
#
# Four of the five platforms (ps5, steam, gog, epic) source from
# `cdn.simpleicons.org/<slug>/000000`. Switch 2 sources from the
# iconify `mdi:nintendo-switch` SVG because simpleicons dropped the
# `nintendoswitch` slug (returns 404 as of the 2026-05-17 audit).
# Both providers serve the same shape of asset: a 24x24 (or 32x32)
# viewBox SVG with `fill="#000000"`. The square gate accepts both.
#
# SQUARE-SOURCE GATE: every source is downloaded into a staging
# tmpdir, then probed for aspect ratio. SVGs parse the `viewBox`
# (preferring it over the legacy `width`/`height` since most brand
# SVGs scale via the viewBox); PNGs use `Vips::Image` to read pixel
# dimensions. A source is accepted only if its width-to-height
# ratio falls inside [0.9, 1.1] — that's the "approximately square"
# rule the tile + detail page layouts assume. Non-square or
# unreachable sources emit a `[MISS]` summary line for that
# platform and leave the on-disk PNGs untouched.
#
# Usage:
#
#   bin/rails pito:platform_logos:download

require "net/http"
require "uri"
require "fileutils"
require "image_processing/vips"

namespace :pito do
  namespace :platform_logos do
    # Canonical 5-platform mapping. Order is the project's display
    # order — also the order `KNOWN_LOGOS` reuses in
    # `PlatformLogosHelper` (PS5 wins over Switch2 over Steam etc.
    # when a game touches multiple).
    #
    # Four entries point at `cdn.simpleicons.org/<slug>/000000`; the
    # fifth (switch2) points at the iconify `mdi:nintendo-switch`
    # SVG with `?color=%23000000`. Both pin the SVG fill to solid
    # black. No silent fallback chain at runtime — every slug picks
    # the SINGLE URL recorded below; misses are reported as `[MISS]`.
    PLATFORM_LOGO_SOURCES = [
      {
        slug: "ps5",
        provider: "simpleicons",
        url: "https://cdn.simpleicons.org/playstation/000000"
      },
      # switch2: tried sources (2026-05-17 audit, all required to be
      # monochrome black + roughly square):
      #   - cdn.simpleicons.org/nintendoswitch/000000 -> HTTP 404
      #     (slug removed from simpleicons; was the original source)
      #   - cdn.simpleicons.org/nintendo-switch/000000 -> HTTP 404
      #   - upload.wikimedia.org/.../Nintendo_Switch_2_logo.svg
      #     -> HTTP 200 but colored (not monochrome) — fails the
      #     black-fill requirement
      #   - api.iconify.design/cib:nintendo-switch.svg
      #     -> HTTP 200, 32x32 viewBox, fill="#000000" (viable
      #     backup if mdi ever disappears)
      #   - api.iconify.design/fa-brands:nintendo-switch.svg
      #     -> HTTP 200 but viewBox 448x512 (not square; fails the
      #     [0.9, 1.1] aspect gate)
      #   - api.iconify.design/logos:nintendo-switch.svg
      #     -> HTTP 404 (not in the logos set)
      #   - api.iconify.design/simple-icons:nintendoswitch.svg
      #     -> HTTP 200 (iconify mirror still serves the dropped
      #     simpleicons slug; viable backup but skipped to avoid
      #     depending on a deprecated slug shadowed by a mirror)
      # winner: api.iconify.design/mdi:nintendo-switch.svg
      #   - HTTP 200, 24x24 viewBox, fill="#000000", ~570B
      {
        slug: "switch2",
        provider: "iconify-mdi",
        url: "https://api.iconify.design/mdi:nintendo-switch.svg?color=%23000000"
      },
      {
        slug: "steam",
        provider: "simpleicons",
        url: "https://cdn.simpleicons.org/steam/000000"
      },
      {
        slug: "gog",
        provider: "simpleicons",
        url: "https://cdn.simpleicons.org/gogdotcom/000000"
      },
      {
        slug: "epic",
        provider: "simpleicons",
        url: "https://cdn.simpleicons.org/epicgames/000000"
      }
    ].freeze

    PLATFORM_LOGO_SIZES = [ 16, 64 ].freeze

    # Anything shorter than this is treated as a "not a real image"
    # response (HTML error page, empty body, SVG-shaped placeholder
    # error). Triggers a [MISS] for that slug.
    MIN_SOURCE_BYTES = 256

    # Aspect-ratio acceptance window. width / height must fall
    # inside [SQUARE_RATIO_MIN, SQUARE_RATIO_MAX] for the source
    # to be accepted. 0.9..1.1 = "approximately square". simpleicons
    # SVGs are all 24x24 viewBox so they pass cleanly; the gate
    # stays in place so the contract is enforced even if upstream
    # changes shape.
    SQUARE_RATIO_MIN = 0.9
    SQUARE_RATIO_MAX = 1.1

    # The CDN is permissive on UA but we send a descriptive
    # identifier for politeness + log-trail.
    USER_AGENT = "Pito/0.1 platform-logos rake task (https://pitomd.com)"

    desc "Fetch best-available brand logos and resize to 16/64 PNG"
    task download: :environment do
      target_dir = Rails.public_path.join("platform_logos")
      FileUtils.mkdir_p(target_dir)

      tmp_root = Rails.root.join("tmp", "platform_logos_src")
      FileUtils.mkdir_p(tmp_root)

      summary = []

      PLATFORM_LOGO_SOURCES.each do |entry|
        slug = entry[:slug]
        result = try_fetch(slug, entry, tmp_root)

        if result.nil?
          summary << "[MISS] #{slug.ljust(8)} no square source available; on-disk files left untouched"
          next
        end

        src_path = result[:path]
        provider = result[:provider]
        src_bytes = result[:bytes]
        src_ext = result[:ext]
        src_dims = result[:dimensions]

        # Wipe any prior 16/64 outputs for this slug so we never
        # leave a stale variant if a future change drops a size.
        Dir.glob(target_dir.join("#{slug}-*.png")).each { |f| File.delete(f) }

        out_sizes = {}
        begin
          PLATFORM_LOGO_SIZES.each do |size|
            out_path = target_dir.join("#{slug}-#{size}.png")
            ImageProcessing::Vips
              .source(src_path)
              .loader(svg_unlimited: true)
              .resize_to_fit(size, size)
              .convert("png")
              .call(destination: out_path.to_s)
            out_sizes[size] = File.size(out_path)
          end
        rescue StandardError => e
          warn "[pito:platform_logos] WARN: #{slug} resize raised " \
               "#{e.class}: #{e.message}; skipped."
          summary << "[FAIL] #{slug.ljust(8)} source=#{provider} (#{format_bytes(src_bytes)} #{src_ext.upcase} #{src_dims}) -> resize failed"
          next
        end

        # SQUARE-GUARD ASSERTION: post-resize, verify every output
        # is exactly the requested size in BOTH dimensions. If vips
        # ever drifts (loader bug, unexpected source shape), this
        # turns a silent strip into a [FAIL] summary line.
        post_resize_ok = PLATFORM_LOGO_SIZES.all? do |size|
          out_path = target_dir.join("#{slug}-#{size}.png")
          img = Vips::Image.new_from_file(out_path.to_s)
          img.width == size && img.height == size
        end
        unless post_resize_ok
          summary << "[FAIL] #{slug.ljust(8)} source=#{provider} (#{format_bytes(src_bytes)} #{src_ext.upcase} #{src_dims}) -> non-square output (square-guard tripped)"
          next
        end

        summary << "[OK]   #{slug.ljust(8)} source=#{provider} " \
                   "(#{format_bytes(src_bytes)} #{src_ext.upcase} #{src_dims}) " \
                   "-> 64.png #{format_bytes(out_sizes[64])}, " \
                   "16.png #{format_bytes(out_sizes[16])}"
      end

      puts ""
      puts "=== platform_logos summary ==="
      summary.each { |line| puts line }
    end

    def try_fetch(slug, source, tmp_root)
      url = source[:url]
      provider = source[:provider]
      response = fetch_logo(url)

      unless response.is_a?(Net::HTTPSuccess)
        warn "[pito:platform_logos] WARN: #{slug} source=#{provider} " \
             "returned HTTP #{response.code} for #{url}; skipping."
        return nil
      end

      body = response.body.to_s
      if body.bytesize < MIN_SOURCE_BYTES
        warn "[pito:platform_logos] WARN: #{slug} source=#{provider} " \
             "returned #{body.bytesize} bytes (< #{MIN_SOURCE_BYTES}); " \
             "treating as failure; skipping."
        return nil
      end

      ext = source_ext(url, response)
      path = tmp_root.join("#{slug}-candidate.#{ext}")
      File.binwrite(path, body)

      dims = measure_dimensions(path, ext)
      if dims.nil?
        warn "[pito:platform_logos] WARN: #{slug} source=#{provider} " \
             "could not determine source dimensions; skipping."
        return nil
      end

      width, height = dims
      ratio = width.to_f / height
      unless ratio.between?(SQUARE_RATIO_MIN, SQUARE_RATIO_MAX)
        warn "[pito:platform_logos] WARN: #{slug} source=#{provider} " \
             "rejected: source #{width}x#{height} (ratio #{ratio.round(2)}) " \
             "fails square gate #{SQUARE_RATIO_MIN}..#{SQUARE_RATIO_MAX}; skipping."
        return nil
      end

      {
        path: path,
        provider: provider,
        bytes: body.bytesize,
        ext: ext,
        dimensions: "#{width}x#{height}"
      }
    rescue StandardError => e
      warn "[pito:platform_logos] WARN: #{slug} source=#{provider} " \
           "raised #{e.class}: #{e.message}; skipping."
      nil
    end

    # Return [width, height] for the candidate source file, or nil
    # if we cannot determine dimensions. SVGs are parsed for the
    # `viewBox` attribute first (the only dimension that reliably
    # tracks the rendered aspect ratio across brand SVGs); legacy
    # `width`/`height` attributes are the fallback. Raster images
    # round-trip through `Vips::Image`.
    def measure_dimensions(path, ext)
      if ext == "svg"
        measure_svg_dimensions(path)
      else
        img = Vips::Image.new_from_file(path.to_s)
        [ img.width, img.height ]
      end
    rescue StandardError
      nil
    end

    def measure_svg_dimensions(path)
      head = File.binread(path, 4096).to_s
      viewbox_match = head.match(/viewBox\s*=\s*"([^"]+)"/i)
      if viewbox_match
        parts = viewbox_match[1].split(/[\s,]+/).map(&:to_f)
        if parts.length == 4 && parts[2].positive? && parts[3].positive?
          return [ parts[2], parts[3] ]
        end
      end

      width_match = head.match(/\bwidth\s*=\s*"([0-9.]+)/i)
      height_match = head.match(/\bheight\s*=\s*"([0-9.]+)/i)
      if width_match && height_match
        w = width_match[1].to_f
        h = height_match[1].to_f
        return [ w, h ] if w.positive? && h.positive?
      end

      nil
    end

    # Guess the file extension from the URL (`.svg`, `.png`) or
    # fall back to the response's Content-Type. simpleicons CDN
    # returns SVG with `image/svg+xml`; the URL path has no
    # extension (`/playstation/000000`) so the Content-Type branch
    # is the load-bearing one for those. iconify URLs DO carry an
    # `.svg` extension in the path (e.g. `mdi:nintendo-switch.svg`),
    # so the URL branch lights up first.
    def source_ext(url, response)
      uri_ext = File.extname(URI.parse(url).path).delete_prefix(".").downcase
      return uri_ext if %w[svg png jpg jpeg webp].include?(uri_ext)

      ct = response["content-type"].to_s.split(";").first.to_s.strip
      case ct
      when "image/svg+xml" then "svg"
      when "image/png"     then "png"
      when "image/jpeg"    then "jpg"
      when "image/webp"    then "webp"
      else "bin"
      end
    end

    def format_bytes(bytes)
      return "0B" if bytes.nil? || bytes.zero?
      return "#{bytes}B" if bytes < 1024

      "#{(bytes / 1024.0).round(1)}KB"
    end

    # Issue the GET via Net::HTTP. Follows up to 3 redirects (the
    # CDNs occasionally 302 through a regional edge before serving
    # the asset). Plain `Net::HTTP.get_response` does NOT follow
    # redirects on its own.
    def fetch_logo(url, redirects_remaining: 3)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => USER_AGENT)
        http.request(req)
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
