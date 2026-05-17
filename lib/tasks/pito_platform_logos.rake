# Phase 27 v2 spec 07 — local-source platform-logo generator (v7).
#
# One-shot Rake task that reads each platform's brand logo from a
# local source file under `lib/support/platforms/` and writes
# resized PNGs in TWO color variants (with transparency for
# antialiasing) to `public/platforms/`. Two sizes × two colors per
# platform:
#
#   - <key>-16-black.png   tile footers / list rows (light theme)
#   - <key>-64-black.png   detail page (light theme, high-DPI)
#   - <key>-16-white.png   tile footers / list rows (dark theme)
#   - <key>-64-white.png   detail page (dark theme, high-DPI)
#
# Three platforms covered: PS5, Switch 2, Steam. GoG and Epic are
# intentionally dropped — the project no longer ships their assets.
# Total output count: 3 platforms × 2 sizes × 2 colors = 12 files.
#
# Source files (placed by the user under `lib/support/platforms/`)
# carry brand-natural filenames, not the canonical platform keys we
# use elsewhere. The `PLATFORM_LOGO_SOURCES` table is the lookup
# from canonical key (`ps5` / `switch2` / `steam`) to source
# filename (`playstation.png` / `switch.png` / `steam.png`).
#
# Output rules:
#
#   - Every visible pixel is forced to a single solid color: either
#     RGB(0, 0, 0) for the BLACK variant or RGB(255, 255, 255) for
#     the WHITE variant. We achieve this by computing a NEW alpha
#     channel from the source's LUMINANCE (dark pixels in source ->
#     opaque in output, light pixels in source -> transparent in
#     output) and bandjoining that alpha onto a freshly created
#     solid-color RGB image of the same dimensions. This is the most
#     robust path: there is no way for any source color to leak
#     through because we never reference the source RGB in the
#     output bands.
#   - The luminance-derived alpha is computed ONCE per source and
#     reused for both color variants — same silhouette, different
#     fill color. This keeps the antialiased edges pixel-identical
#     between the black and white variants of the same logo.
#   - Source alpha is NOT used as the output alpha. Real brand-logo
#     PNGs from the user's `lib/support/platforms/` folder ship with
#     a FILLED disc-shaped alpha mask (not a silhouette mask), so
#     reusing source alpha would paint the entire disc opaque
#     instead of just the logo shape. Computing alpha from luminance
#     handles both filled-background sources and transparent-
#     background ones consistently.
#   - PNGs ship with transparency (no background fill).
#   - Convert luminance -> alpha FIRST on the source-resolution image
#     so the inversion / colourspace step operates on full pixel
#     fidelity. THEN bandjoin the color RGB + alpha and resize so
#     libvips' shrink kernel produces clean anti-aliased edges at
#     the small sizes.
#
# Cleanup contract:
#
#   Before any per-platform iteration, every existing file directly
#   under `public/platforms/` is deleted (the directory itself is
#   preserved). This guarantees that removing a size from
#   `PLATFORM_LOGO_SIZES`, removing a color from `PLATFORM_LOGO_COLORS`,
#   removing a platform from `PLATFORM_LOGO_SOURCES`, or renaming an
#   output never leaves an orphan file on disk. The dropped-128 case
#   and the older two-name-pattern (`ps5-16.png` pre-rename) are the
#   motivating examples: orphans from a prior naming scheme are wiped
#   before the fresh 16 / 64 × black / white set is rendered.
#
#   The missing-source case has its own contract: if a platform's
#   source file is absent, the rake task warns + skips that platform
#   and the wipe-first step is bypassed so pre-existing outputs for
#   the missing slug survive. This keeps a temporarily-missing source
#   from nuking a working asset set.
#
# Usage:
#
#   bin/rails pito:platform_logos:download

require "fileutils"

namespace :pito do
  namespace :platform_logos do
    # Canonical-key -> source-filename mapping. Order is the
    # project's display order (PS5 > Switch2 > Steam) and matches
    # `PlatformLogosHelper::KNOWN_LOGOS`.
    PLATFORM_LOGO_SOURCES = [
      { slug: "ps5",     filename: "playstation.png" },
      { slug: "switch2", filename: "switch.png" },
      { slug: "steam",   filename: "steam.png" }
    ].freeze

    PLATFORM_LOGO_SIZES = [ 16, 64 ].freeze

    # Color variants. Each variant produces a separate output file
    # per (platform, size); the consumer picks the variant based on
    # the active theme (`black` on light theme, `white` on dark
    # theme). The order is the project's display priority — `black`
    # first because the light theme is the default; `white` follows.
    PLATFORM_LOGO_COLORS = [
      { name: "black", rgb: [ 0,   0,   0 ] },
      { name: "white", rgb: [ 255, 255, 255 ] }
    ].freeze

    # Output folder under `public/`. Renamed from `platform_logos`
    # to `platforms` so the on-disk path matches the canonical
    # noun the rest of the codebase uses.
    OUTPUT_DIRNAME = "platforms".freeze

    # Source folder under the repo (`lib/support/platforms/`).
    # Tests may override via `PITO_PLATFORM_LOGOS_SOURCE_DIR=...`
    # so the rake task can run against a fixture folder without
    # mutating the on-disk sources.
    DEFAULT_SOURCE_DIR = Rails.root.join("lib", "support", "platforms").freeze

    desc "Render local brand logos to 16/64 PNG (monochrome black + alpha)"
    task download: :environment do
      target_dir = Rails.public_path.join(OUTPUT_DIRNAME)
      FileUtils.mkdir_p(target_dir)

      source_dir = ENV["PITO_PLATFORM_LOGOS_SOURCE_DIR"].present? ?
        Pathname.new(ENV["PITO_PLATFORM_LOGOS_SOURCE_DIR"]) :
        DEFAULT_SOURCE_DIR

      # Wipe-first cleanup: delete every existing file directly under
      # `public/platforms/`, but ONLY if every source we are about to
      # render is present. If any source is missing we keep the prior
      # outputs untouched so a momentarily-absent source can't nuke a
      # working asset set. The missing-source path will warn + [MISS]
      # for the affected slug and re-render the rest in place.
      all_sources_present = PLATFORM_LOGO_SOURCES.all? do |entry|
        File.exist?(source_dir.join(entry[:filename]))
      end

      if all_sources_present
        Dir.glob(target_dir.join("*")).each do |path|
          File.delete(path) if File.file?(path)
        end
      end

      summary = []

      PLATFORM_LOGO_SOURCES.each do |entry|
        slug = entry[:slug]
        src_path = source_dir.join(entry[:filename])

        unless File.exist?(src_path)
          warn "[pito:platform_logos] WARN: #{slug} source missing " \
               "at #{src_path}; skipping."
          summary << "[MISS] #{slug.ljust(8)} source missing at #{entry[:filename]}; on-disk files left untouched"
          next
        end

        out_sizes = {}
        src_dims = nil
        begin
          src_img = Vips::Image.new_from_file(src_path.to_s)
          src_dims = "#{src_img.width}x#{src_img.height}"

          # Compute the luminance-derived alpha ONCE per source so
          # the silhouette is pixel-identical across all 4 outputs
          # (2 sizes × 2 colors). The alpha mask is recolored — not
          # re-derived — between variants.
          alpha_full = derive_silhouette_alpha(src_path.to_s)

          PLATFORM_LOGO_SIZES.each do |size|
            PLATFORM_LOGO_COLORS.each do |color|
              out_path = target_dir.join("#{slug}-#{size}-#{color[:name]}.png")
              render_solid_color_png(alpha_full, color[:rgb], out_path.to_s, size)
              out_sizes["#{size}-#{color[:name]}"] = File.size(out_path)
            end
          end
        rescue StandardError => e
          warn "[pito:platform_logos] WARN: #{slug} render raised " \
               "#{e.class}: #{e.message}; skipped."
          summary << "[FAIL] #{slug.ljust(8)} source=#{entry[:filename]} -> render failed (#{e.class})"
          next
        end

        # Post-render square-guard: every output must be exactly
        # the requested size in BOTH dimensions. If libvips drifts,
        # this turns a silent shape change into a [FAIL] line.
        post_resize_ok = PLATFORM_LOGO_SIZES.all? do |size|
          PLATFORM_LOGO_COLORS.all? do |color|
            out_path = target_dir.join("#{slug}-#{size}-#{color[:name]}.png")
            img = Vips::Image.new_from_file(out_path.to_s)
            img.width == size && img.height == size
          end
        end
        unless post_resize_ok
          summary << "[FAIL] #{slug.ljust(8)} source=#{entry[:filename]} (#{src_dims}) -> non-square output (square-guard tripped)"
          next
        end

        size_summary = PLATFORM_LOGO_SIZES.flat_map { |s|
          PLATFORM_LOGO_COLORS.map { |c| "#{s}-#{c[:name]}.png #{format_bytes(out_sizes["#{s}-#{c[:name]}"])}" }
        }.join(", ")
        summary << "[OK]   #{slug.ljust(8)} source=#{entry[:filename]} (#{src_dims}) -> #{size_summary}"
      end

      puts ""
      puts "=== platform_logos summary ==="
      summary.each { |line| puts line }
    end

    # Two-stage pipeline:
    #
    #   1. `derive_silhouette_alpha(src_path)` — load source, run the
    #      luminance + invert + boost pipeline ONCE, return a
    #      source-resolution single-band uchar alpha mask. The mask is
    #      pure silhouette: high values where the logo is, low values
    #      where the background is.
    #   2. `render_solid_color_png(alpha_full, rgb, out_path, size)` —
    #      build a 3-band solid-color RGB image at the alpha mask's
    #      resolution, bandjoin the alpha to get RGBA, resize to the
    #      target square. The RGB triple is supplied per color variant
    #      (`[0, 0, 0]` for black, `[255, 255, 255]` for white).
    #
    # Why split the pipeline: the silhouette is identical between the
    # black and white variants of the same logo — only the fill color
    # differs. Computing alpha once and reusing it across both variants
    # keeps the antialiased edges pixel-identical and avoids redundant
    # work.
    #
    # Why a fresh solid-color RGB instead of reusing source RGB: the
    # output is guaranteed to be exactly the requested color on R/G/B
    # because those bands are constructed from a constant image. There
    # is no path for source color to leak through.
    #
    # Why NOT use the source's own alpha as the output alpha: real
    # brand PNGs (the user's `lib/support/platforms/` files) ship with
    # a filled disc-shaped alpha — the whole visible disc is opaque,
    # not just the logo shape. Reusing that alpha would paint the
    # entire disc the fill color. Luminance-derived alpha handles both
    # filled and silhouette source masks the same way.

    # Alpha-contrast multiplier applied to the inverted luminance.
    # 2.0 lifts ps5 (raw max=226) and switch2 (raw max=150) past the
    # opaque ceiling so their silhouettes read as solid, while steam
    # (raw max=255) is unaffected by the clamp. See the v6 boost note
    # for the per-platform numbers.
    ALPHA_BOOST = 2.0

    # Derive a silhouette alpha mask from the source image. Returns a
    # single-band uchar Vips::Image at the source's native resolution.
    # Reusable across color variants.
    def derive_silhouette_alpha(src_path)
      src = Vips::Image.new_from_file(src_path)
      src = src.colourspace(:srgb) unless src.interpretation == :srgb

      # Flatten any existing alpha against white so transparent regions
      # in the source map to a low luminance contribution AFTER the
      # invert (i.e. transparent in source -> transparent in output).
      src = src.flatten(background: [ 255, 255, 255 ]) if src.has_alpha?

      # Convert to single-band luminance. `:b_w` applies the standard
      # sRGB -> luminance weighting (≈0.2126 R + 0.7152 G + 0.0722 B
      # under libvips' default).
      luminance = src.colourspace(:b_w)

      # Take just the luminance band (b_w can leave the image multi-
      # band depending on input). One-band guarantee makes the invert
      # and bandjoin steps unambiguous.
      luminance = luminance.extract_band(0) if luminance.bands > 1

      # Invert: 255 - pixel. Dark logo pixels become near-255 (opaque),
      # white background becomes near-0 (transparent).
      alpha_seed = luminance.invert

      # Boost contrast: multiply then clamp to the 0..255 uchar range.
      # `linear(boost, 0)` returns a float band; the `ifthenelse` clamps
      # values above 255 down to 255 before casting back to :uchar.
      boosted = alpha_seed.linear(ALPHA_BOOST, 0)
      (boosted > 255).ifthenelse(255, boosted).cast(:uchar)
    end

    # Render a solid-color silhouette PNG by bandjoining the pre-
    # computed alpha mask onto a freshly constructed RGB image of the
    # requested color, then resizing to the target square.
    def render_solid_color_png(alpha_full, rgb, out_path, size)
      width  = alpha_full.width
      height = alpha_full.height

      # Build the solid-color RGB image. Each band is a constant image
      # equal to one channel of the requested color. Using
      # `Vips::Image.black(...) + value` (via `linear(0, value)`) is
      # the idiomatic libvips path for "constant-value image at these
      # dims" — multiply input by 0, add the constant, cast back to
      # :uchar so the result is a proper 8-bit band.
      r_band = Vips::Image.black(width, height).linear(0, rgb[0]).cast(:uchar)
      g_band = Vips::Image.black(width, height).linear(0, rgb[1]).cast(:uchar)
      b_band = Vips::Image.black(width, height).linear(0, rgb[2]).cast(:uchar)
      rgb_solid = r_band.bandjoin([ g_band, b_band ])

      # Combine solid-color RGB + computed alpha -> RGBA at source size.
      colored_full = rgb_solid.bandjoin(alpha_full).copy(interpretation: :srgb)

      # Resize LAST so libvips' shrink kernel anti-aliases against the
      # already-correct silhouette alpha mask.
      colored = colored_full.thumbnail_image(size, height: size, size: :force)

      colored.write_to_file(out_path, strip: true)
    end

    def format_bytes(bytes)
      return "0B" if bytes.nil? || bytes.zero?
      return "#{bytes}B" if bytes < 1024

      "#{(bytes / 1024.0).round(1)}KB"
    end
  end
end
