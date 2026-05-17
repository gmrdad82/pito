require "rails_helper"
require "rake"

# Phase 27 v2 spec 07 (v7) — `pito:platform_logos:download` rake task spec.
#
# The rake task reads three brand-named PNG source files from
# `lib/support/platforms/` and writes 16/64 px PNGs in TWO color
# variants (black + white) with preserved alpha for antialiasing to
# `public/platforms/`. This spec drives the task against a tmpdir
# `Rails.public_path` and (via the `PITO_PLATFORM_LOGOS_SOURCE_DIR`
# env override) a fixture-backed source folder so the assertions
# are deterministic and offline.
#
# Coverage:
#
#   - Happy path: every platform produces 4 PNGs at exactly the
#     requested size, all square, all valid PNGs (3 × 2 × 2 = 12).
#   - Color variants: black outputs have R=G=B=0 across all visible
#     pixels; white outputs have R=G=B=255 across all visible pixels.
#   - Silhouette parity: black and white variants of the same
#     (platform, size) share the same alpha mask — same silhouette,
#     different fill.
#   - Transparency: at least some pixels in each output are
#     transparent (alpha == 0).
#   - Wipe-first cleanup: orphan files (from a prior naming scheme)
#     are deleted before fresh writes; only the current 12-file set
#     survives a re-run.
#   - Missing source: the platform reports [MISS] and the other
#     platforms still render successfully; wipe-first is bypassed
#     so pre-existing outputs for the missing slug survive.
#   - Folder-name regression guard: outputs land in
#     `public/platforms/`, NOT `public/platform_logos/`.
#   - Platform / size / color scope: exactly ps5, switch2, steam at
#     16 & 64 px in black + white.
RSpec.describe "pito:platform_logos rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_platform_logos",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:platform_logos:download"] }

  before { task.reenable }

  let(:tmpdir) { Dir.mktmpdir("pito_platform_logos_spec") }
  after { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  # Fixture source folder mirrors the real `lib/support/platforms/`
  # layout. Three RGBA PNGs at 256x256 with a FILLED-alpha white
  # background (alpha == 255 everywhere) plus a colored letter
  # shape on top. This deliberately matches the structure of real
  # brand-logo source PNGs in `lib/support/platforms/`, where the
  # alpha channel covers the whole disc rather than tracing the
  # logo silhouette. The rake task must derive its OWN alpha from
  # luminance — it cannot reuse source alpha or the entire disc
  # comes out painted black.
  let(:fixture_source_dir) { Rails.root.join("spec", "fixtures", "files", "platforms") }

  before do
    allow(Rails).to receive(:public_path).and_return(Pathname.new(tmpdir))
    ENV["PITO_PLATFORM_LOGOS_SOURCE_DIR"] = fixture_source_dir.to_s
  end

  after { ENV.delete("PITO_PLATFORM_LOGOS_SOURCE_DIR") }

  PLATFORMS = %w[ps5 switch2 steam].freeze
  SIZES = [ 16, 64 ].freeze
  COLORS = %w[black white].freeze
  EXPECTED_RGB_MAX = { "black" => 0, "white" => 255 }.freeze

  def each_variant
    PLATFORMS.each do |slug|
      SIZES.each do |size|
        COLORS.each do |color|
          yield slug, size, color
        end
      end
    end
  end

  describe "happy path: every fixture source produces 4 variant PNGs" do
    it "creates `public/platforms/` if missing" do
      expect(Dir.exist?(File.join(tmpdir, "platforms"))).to be(false)
      silence_stream($stdout) { task.invoke }
      expect(Dir.exist?(File.join(tmpdir, "platforms"))).to be(true)
    end

    it "writes 12 PNGs total (3 platforms × 2 sizes × 2 colors)" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        expect(File.exist?(path)).to be(true), "expected #{path} to exist"
      end
      written = Dir.glob(File.join(tmpdir, "platforms", "*.png"))
      expect(written.count).to eq(12)
    end

    it "does NOT write the legacy color-less filenames (`<slug>-<size>.png`)" do
      silence_stream($stdout) { task.invoke }
      legacy = PLATFORMS.flat_map { |slug| SIZES.map { |size| File.join(tmpdir, "platforms", "#{slug}-#{size}.png") } }
      legacy.each do |path|
        expect(File.exist?(path)).to be(false), "expected legacy #{path} NOT to exist"
      end
    end

    it "does NOT write any 128 px output (size dropped)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        COLORS.each do |color|
          path = File.join(tmpdir, "platforms", "#{slug}-128-#{color}.png")
          expect(File.exist?(path)).to be(false), "expected #{path} NOT to exist"
        end
      end
      orphan_128s = Dir.glob(File.join(tmpdir, "platforms", "*-128-*.png"))
      expect(orphan_128s).to be_empty
    end

    it "writes PNGs with the EXACT pixel dimensions requested" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        expect([ img.width, img.height ]).to eq([ size, size ]),
          "expected #{slug}-#{size}-#{color}.png to be #{size}x#{size}, got #{img.width}x#{img.height}"
      end
    end

    it "produces square outputs for every (platform, size, color) combination" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        expect(img.width).to eq(img.height), "expected #{slug}-#{size}-#{color}.png to be square, got #{img.width}x#{img.height}"
      end
    end

    it "writes RGBA PNGs (4 bands — alpha preserved)" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        expect(img.bands).to eq(4),
          "expected #{slug}-#{size}-#{color}.png to be RGBA (4 bands), got #{img.bands}"
      end
    end

    it "writes valid PNG magic bytes for every output" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        expect(File.binread(path, 8).bytes).to eq(
          [ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ]
        ), "#{path} is not a valid PNG"
      end
    end

    it "fills every BLACK variant with pure black on R, G, B bands (max = 0)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        SIZES.each do |size|
          path = File.join(tmpdir, "platforms", "#{slug}-#{size}-black.png")
          img = Vips::Image.new_from_file(path)
          expect(img.extract_band(0).max).to eq(0), "expected #{slug}-#{size}-black.png R band max=0"
          expect(img.extract_band(1).max).to eq(0), "expected #{slug}-#{size}-black.png G band max=0"
          expect(img.extract_band(2).max).to eq(0), "expected #{slug}-#{size}-black.png B band max=0"
        end
      end
    end

    it "fills every WHITE variant with pure white on R, G, B bands (max = 255)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        SIZES.each do |size|
          path = File.join(tmpdir, "platforms", "#{slug}-#{size}-white.png")
          img = Vips::Image.new_from_file(path)
          # Max == 255 on every RGB band proves the fill color is
          # white where the silhouette is visible. The RGB min may
          # drop to 0 in fully-transparent regions because libvips'
          # `thumbnail_image` premultiplies alpha during the shrink
          # — that's a no-op visually (alpha is 0, so RGB doesn't
          # matter), but it means we cannot assert RGB min=255.
          # The visible-area assertion below covers the rendered
          # silhouette where it counts.
          expect(img.extract_band(0).max).to eq(255), "expected #{slug}-#{size}-white.png R band max=255"
          expect(img.extract_band(1).max).to eq(255), "expected #{slug}-#{size}-white.png G band max=255"
          expect(img.extract_band(2).max).to eq(255), "expected #{slug}-#{size}-white.png B band max=255"
        end
      end
    end

    it "paints the WHITE variant silhouette pure white where it's visible (alpha-masked R/G/B >= 250)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        SIZES.each do |size|
          path = File.join(tmpdir, "platforms", "#{slug}-#{size}-white.png")
          img = Vips::Image.new_from_file(path)
          alpha = img.extract_band(3)

          # Visible mask: pixels where alpha is fully opaque (>= 240,
          # mirroring the alpha-max threshold used by the boost
          # assertion above). Inside that mask, R/G/B must be at
          # least 250 — small (≤5) drift comes from libvips'
          # premultiplied-alpha shrink against edge pixels even
          # where the alpha boost saturates. The fill color is white
          # — black would never round up to 250+ here.
          fully_opaque_mask = alpha.relational_const("moreeq", 240)

          [ 0, 1, 2 ].each do |band_idx|
            band = img.extract_band(band_idx)
            # Set non-mask pixels to a sentinel (255) so the global
            # min only reflects pixels inside the visible silhouette.
            in_mask = fully_opaque_mask.ifthenelse(band, 255)
            expect(in_mask.min).to be >= 250,
              "expected #{slug}-#{size}-white.png band #{band_idx} >= 250 across the visible silhouette, got min=#{in_mask.min}"
          end
        end
      end
    end

    it "shares the SAME alpha silhouette between the black and white variant at a given (platform, size)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        SIZES.each do |size|
          black_path = File.join(tmpdir, "platforms", "#{slug}-#{size}-black.png")
          white_path = File.join(tmpdir, "platforms", "#{slug}-#{size}-white.png")
          black_alpha = Vips::Image.new_from_file(black_path).extract_band(3)
          white_alpha = Vips::Image.new_from_file(white_path).extract_band(3)

          # The two alpha bands must be pixel-identical — subtracting
          # one from the other should yield a band whose min and max
          # are both zero.
          diff = black_alpha.subtract(white_alpha)
          expect(diff.abs.max).to eq(0),
            "expected black and white alpha to match for #{slug}-#{size}, got diff max=#{diff.abs.max}"
        end
      end
    end

    it "preserves transparency (every output has some fully-transparent pixels)" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        alpha_min = img.extract_band(3).min
        expect(alpha_min).to eq(0),
          "expected #{slug}-#{size}-#{color}.png to have transparent pixels (alpha min=0), got #{alpha_min}"
      end
    end

    # Regression guard for the bandjoin-onto-source-alpha bug: when
    # the rake task reused the source PNG's filled-disc alpha, the
    # output became a SOLID-colored disc — alpha was 255 (or close to
    # it) across the entire visible disc, with no silhouette structure.
    # A real silhouette has both transparent and opaque pixels with a
    # meaningful spread, not a single dominant alpha value. We assert
    # both `alpha_max > 0` (the logo is visible at all) and the alpha
    # band's `deviate` (population stddev) is above a floor that a
    # uniform-opaque disc could never reach.
    it "produces a silhouette alpha — not a uniformly opaque disc" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        alpha = img.extract_band(3)
        expect(alpha.max).to be > 0,
          "expected #{slug}-#{size}-#{color}.png to have visible (non-zero) alpha somewhere"
        expect(alpha.deviate).to be > 10,
          "expected #{slug}-#{size}-#{color}.png alpha band to vary across the image, got deviate=#{alpha.deviate.round(2)}"
      end
    end

    # The same regression also showed up as the alpha band being
    # nearly all-opaque. A real silhouette of a logo-on-transparent-
    # background should have a meaningful share of pixels in the LOW
    # alpha bucket (the background) AND a meaningful share in the
    # upper alpha range (the logo shape itself). We check that both
    # buckets are non-empty on every output.
    it "has both transparent-background pixels and visible logo pixels (silhouette structure)" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        alpha = img.extract_band(3)

        low_frac  = alpha.relational_const("less", 16).avg / 255.0
        high_frac = alpha.relational_const("more", 64).avg / 255.0

        expect(low_frac).to be > 0.05,
          "expected #{slug}-#{size}-#{color}.png to have at least 5% transparent-background pixels, got #{(low_frac * 100).round(1)}%"
        expect(high_frac).to be > 0.05,
          "expected #{slug}-#{size}-#{color}.png to have at least 5% visible (alpha>64) logo pixels, got #{(high_frac * 100).round(1)}%"
      end
    end

    # v6 boost regression guard: the v5 luminance-only pipeline left
    # ps5 at alpha_max=242 and switch2 at alpha_max=174, which read
    # as washed-out. The v6 contrast boost (`ALPHA_BOOST = 2.0` then
    # clamp at 255) lifts every silhouette to full opacity.
    it "boosts the logo silhouette to fully opaque (alpha_max >= 240) on every output" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        alpha_max = img.extract_band(3).max
        expect(alpha_max).to be >= 240,
          "expected #{slug}-#{size}-#{color}.png alpha max >= 240 (solid silhouette), got #{alpha_max}"
      end
    end

    it "keeps the visible logo area opaque (avg alpha over non-near-zero pixels >= 150)" do
      silence_stream($stdout) { task.invoke }
      each_variant do |slug, size, color|
        path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
        img = Vips::Image.new_from_file(path)
        alpha = img.extract_band(3)
        total = alpha.width * alpha.height

        visible_mask  = alpha.relational_const("more", 16).divide(255)
        visible_frac  = visible_mask.avg
        visible_count = visible_frac * total
        visible_sum   = visible_mask.multiply(alpha).avg * total
        visible_avg   = visible_count.positive? ? visible_sum / visible_count : 0.0

        expect(visible_avg).to be >= 150,
          "expected #{slug}-#{size}-#{color}.png visible-area alpha avg >= 150, got #{visible_avg.round(2)} over #{visible_count.round} visible pixels"
      end
    end

    it "prints a per-platform [OK] summary line" do
      output = capture_stdout { task.invoke }
      PLATFORMS.each do |slug|
        expect(output).to match(/\[OK\]\s+#{slug}\s/), "missing summary line for #{slug}"
      end
    end

    it "names the source filename in each summary line" do
      output = capture_stdout { task.invoke }
      expect(output).to match(/\[OK\]\s+ps5\s+source=playstation\.png/)
      expect(output).to match(/\[OK\]\s+switch2\s+source=switch\.png/)
      expect(output).to match(/\[OK\]\s+steam\s+source=steam\.png/)
    end

    it "names BOTH color variants in each summary line" do
      output = capture_stdout { task.invoke }
      PLATFORMS.each do |slug|
        expect(output).to match(/\[OK\]\s+#{slug}.*16-black\.png/), "missing 16-black summary entry for #{slug}"
        expect(output).to match(/\[OK\]\s+#{slug}.*16-white\.png/), "missing 16-white summary entry for #{slug}"
        expect(output).to match(/\[OK\]\s+#{slug}.*64-black\.png/), "missing 64-black summary entry for #{slug}"
        expect(output).to match(/\[OK\]\s+#{slug}.*64-white\.png/), "missing 64-white summary entry for #{slug}"
      end
    end
  end

  # The color-fill assertion above (R=G=B=0 for black, R=G=B=255 for
  # white) is the contract that the previous regression silently broke.
  # These two specs are a belt-and-braces self-check: they prove the
  # assertion is real, not vacuous.
  describe "color-fill assertion self-check (would catch source-color leak)" do
    let(:colored_fixture) { fixture_source_dir.join("steam.png") }

    it "the raw colored fixture is NOT all-black on at least one RGB band" do
      img = Vips::Image.new_from_file(colored_fixture.to_s)
      max_per_band = [ img.extract_band(0).max, img.extract_band(1).max, img.extract_band(2).max ]
      expect(max_per_band.max).to be > 0,
        "fixture must have non-zero RGB content (white background) so the would-fail check is meaningful; got #{max_per_band.inspect}"
    end

    it "feeding the colored fixture through the renderer produces true black RGB for the black variant" do
      out_path = File.join(tmpdir, "self-check-64-black.png")

      # Invoke the task once so the task body's `def` helpers
      # (`derive_silhouette_alpha`, `render_solid_color_png`) are
      # wired up as top-level methods (Rake DSL `def` inside a task
      # block lands on Object as a private method).
      silence_stream($stdout) { task.invoke }
      task.reenable

      alpha = TOPLEVEL_BINDING.receiver.send(:derive_silhouette_alpha, colored_fixture.to_s)
      TOPLEVEL_BINDING.receiver.send(:render_solid_color_png, alpha, [ 0, 0, 0 ], out_path, 64)

      img = Vips::Image.new_from_file(out_path)
      expect(img.extract_band(0).max).to eq(0)
      expect(img.extract_band(1).max).to eq(0)
      expect(img.extract_band(2).max).to eq(0)
      expect(img.extract_band(3).max).to be > 0
    end

    it "feeding the colored fixture through the renderer produces white RGB for the white variant" do
      out_path = File.join(tmpdir, "self-check-64-white.png")

      silence_stream($stdout) { task.invoke }
      task.reenable

      alpha = TOPLEVEL_BINDING.receiver.send(:derive_silhouette_alpha, colored_fixture.to_s)
      TOPLEVEL_BINDING.receiver.send(:render_solid_color_png, alpha, [ 255, 255, 255 ], out_path, 64)

      img = Vips::Image.new_from_file(out_path)
      # R/G/B max == 255 — the fill color is white. (RGB min may drop
      # to 0 in transparent regions due to libvips' premultiplied-
      # alpha thumbnail shrink; visible silhouette assertions live in
      # the happy-path block above.)
      expect(img.extract_band(0).max).to eq(255)
      expect(img.extract_band(1).max).to eq(255)
      expect(img.extract_band(2).max).to eq(255)
      expect(img.extract_band(3).max).to be > 0
    end
  end

  describe "wipe-first cleanup: orphans from prior runs are removed" do
    it "deletes an orphan -128 file that lingers from a prior size set" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      orphan = File.join(target_dir, "ps5-128-black.png")
      File.binwrite(orphan, "STALE-ORPHAN-128")

      silence_stream($stdout) { task.invoke }

      expect(File.exist?(orphan)).to be(false),
        "expected wipe-first to delete the orphan ps5-128-black.png"
    end

    it "deletes legacy color-less names (`<slug>-<size>.png`) from the pre-v7 naming scheme" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      legacy = File.join(target_dir, "ps5-16.png")
      File.binwrite(legacy, "STALE-LEGACY-NAME")

      silence_stream($stdout) { task.invoke }

      expect(File.exist?(legacy)).to be(false),
        "expected wipe-first to delete legacy ps5-16.png orphan from the pre-v7 naming scheme"
    end

    it "deletes an unrelated orphan file (anything in the folder is fair game)" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      orphan = File.join(target_dir, "orphan-stale.png")
      File.binwrite(orphan, "ARBITRARY-ORPHAN")

      silence_stream($stdout) { task.invoke }

      expect(File.exist?(orphan)).to be(false),
        "expected wipe-first to delete arbitrary orphan files in public/platforms/"
    end

    it "leaves exactly 12 files in the output dir after a clean run from an empty folder" do
      silence_stream($stdout) { task.invoke }
      entries = Dir.children(File.join(tmpdir, "platforms"))
      expect(entries.sort).to eq(%w[
        ps5-16-black.png
        ps5-16-white.png
        ps5-64-black.png
        ps5-64-white.png
        steam-16-black.png
        steam-16-white.png
        steam-64-black.png
        steam-64-white.png
        switch2-16-black.png
        switch2-16-white.png
        switch2-64-black.png
        switch2-64-white.png
      ])
    end

    it "leaves exactly 12 files in the output dir after a re-run with prior content" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      # Seed the folder with assorted orphans: legacy color-less,
      # dropped size, dropped platform, and a non-PNG.
      File.binwrite(File.join(target_dir, "ps5-128-black.png"), "X")
      File.binwrite(File.join(target_dir, "ps5-16.png"),        "Y")  # legacy color-less
      File.binwrite(File.join(target_dir, "epic-64-white.png"), "Z")
      File.binwrite(File.join(target_dir, "junk.txt"),          "Q")

      silence_stream($stdout) { task.invoke }

      entries = Dir.children(target_dir)
      expect(entries.sort).to eq(%w[
        ps5-16-black.png
        ps5-16-white.png
        ps5-64-black.png
        ps5-64-white.png
        steam-16-black.png
        steam-16-white.png
        steam-64-black.png
        steam-64-white.png
        switch2-16-black.png
        switch2-16-white.png
        switch2-64-black.png
        switch2-64-white.png
      ])
    end
  end

  describe "folder-name regression guard" do
    it "writes outputs under `public/platforms/`, NOT the retired `public/platform_logos/`" do
      silence_stream($stdout) { task.invoke }
      expect(Dir.exist?(File.join(tmpdir, "platforms"))).to be(true)
      expect(Dir.exist?(File.join(tmpdir, "platform_logos"))).to be(false)
    end

    it "names the output dirname constant as `platforms`" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      expect(source).to match(/OUTPUT_DIRNAME\s*=\s*"platforms"/)
      expect(source).not_to match(/OUTPUT_DIRNAME\s*=\s*"platform_logos"/)
    end
  end

  describe "platform / size / color scope" do
    it "covers exactly ps5, switch2, steam in the source table" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      table_block = source[/PLATFORM_LOGO_SOURCES\s*=\s*\[.*?\]\.freeze/m]
      expect(table_block).to be_present, "could not locate PLATFORM_LOGO_SOURCES table"
      slugs = table_block.scan(/slug:\s*"([^"]+)"/).flatten
      expect(slugs).to eq(%w[ps5 switch2 steam])
    end

    it "does NOT list gog or epic anywhere in the source table" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      table_block = source[/PLATFORM_LOGO_SOURCES\s*=\s*\[.*?\]\.freeze/m]
      expect(table_block).not_to include("gog")
      expect(table_block).not_to include("epic")
    end

    it "declares 16 and 64 as the two output sizes (128 dropped)" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      expect(source).to match(/PLATFORM_LOGO_SIZES\s*=\s*\[\s*16\s*,\s*64\s*\]/)
      expect(source).not_to match(/PLATFORM_LOGO_SIZES\s*=\s*\[\s*16\s*,\s*64\s*,\s*128\s*\]/)
    end

    it "declares black and white as the two color variants" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      colors_block = source[/PLATFORM_LOGO_COLORS\s*=\s*\[.*?\]\.freeze/m]
      expect(colors_block).to be_present, "could not locate PLATFORM_LOGO_COLORS table"
      names = colors_block.scan(/name:\s*"([^"]+)"/).flatten
      expect(names).to eq(%w[black white])
    end
  end

  describe "missing source: a single platform skipped, others still render" do
    let(:partial_source_dir) { Dir.mktmpdir("pito_platform_logos_partial") }
    after { FileUtils.remove_entry(partial_source_dir) if Dir.exist?(partial_source_dir) }

    before do
      FileUtils.cp(fixture_source_dir.join("playstation.png"), partial_source_dir)
      FileUtils.cp(fixture_source_dir.join("steam.png"),       partial_source_dir)
      # switch.png intentionally absent
      ENV["PITO_PLATFORM_LOGOS_SOURCE_DIR"] = partial_source_dir
    end

    it "logs a WARN for the missing source" do
      silence_stream($stdout) do
        expect { task.invoke }.to output(
          /\[pito:platform_logos\] WARN: switch2 source missing/
        ).to_stderr
      end
    end

    it "emits a [MISS] summary line for the missing platform" do
      output = capture_stdout { silence_stream($stderr) { task.invoke } }
      expect(output).to match(/\[MISS\]\s+switch2\s+source missing/)
    end

    it "still writes the other 2 platforms' 4 variants each (8 files)" do
      silence_stream($stdout) { silence_stream($stderr) { task.invoke } }
      %w[ps5 steam].each do |slug|
        SIZES.each do |size|
          COLORS.each do |color|
            path = File.join(tmpdir, "platforms", "#{slug}-#{size}-#{color}.png")
            expect(File.exist?(path)).to be(true), "expected #{path} to exist"
          end
        end
      end
    end

    it "does NOT write any switch2-*.png output" do
      silence_stream($stdout) { silence_stream($stderr) { task.invoke } }
      switch2_files = Dir.glob(File.join(tmpdir, "platforms", "switch2-*.png"))
      expect(switch2_files).to be_empty
    end

    it "does NOT delete pre-existing switch2-*.png files when the source is missing (wipe-first bypassed)" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      stale_64 = File.join(target_dir, "switch2-64-black.png")
      stale_16 = File.join(target_dir, "switch2-16-white.png")
      File.binwrite(stale_64, "STALE-64-BYTES" * 10)
      File.binwrite(stale_16, "STALE-16-BYTES" * 10)

      silence_stream($stdout) { silence_stream($stderr) { task.invoke } }

      expect(File.exist?(stale_64)).to be(true)
      expect(File.exist?(stale_16)).to be(true)
      expect(File.binread(stale_64)).to start_with("STALE-64-BYTES")
    end

    it "exits 0 — does not raise" do
      expect {
        silence_stream($stdout) { silence_stream($stderr) { task.invoke } }
      }.not_to raise_error
    end
  end

  describe "idempotency: re-running overwrites prior files for the slug" do
    it "replaces a pre-existing ps5-16-black.png with the freshly rendered bytes" do
      target_dir = File.join(tmpdir, "platforms")
      FileUtils.mkdir_p(target_dir)
      stale = File.join(target_dir, "ps5-16-black.png")
      File.binwrite(stale, "STALE-BYTES-NOT-A-REAL-PNG")

      silence_stream($stdout) { task.invoke }

      # Verify it's a real PNG now, not the stub bytes.
      expect(File.binread(stale, 8).bytes.first(8))
        .to eq([ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ])
    end
  end

  # ----- helpers -----

  def silence_stream(stream)
    original = stream.dup
    stream.reopen(File.new(File::NULL, "w"))
    yield
  ensure
    stream.reopen(original) if original
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
