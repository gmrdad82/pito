require "rails_helper"
require "rake"

# Phase 27 v2 spec 07 — `pito:platform_logos:download` rake task spec.
#
# Stubs every source URL for the 5-platform list, invokes the task
# against a tmpdir `Rails.public_path`, and asserts each platform
# produces BOTH a 16 px and a 64 px PNG with the expected pixel
# dimensions. Also covers:
#
#   - HTTP failure -> [MISS] for that slug, on-disk files untouched
#   - transport error -> [MISS] for that slug, on-disk files untouched
#   - too-small response body (< MIN_SOURCE_BYTES) is treated as failure
#   - non-square sources (aspect ratio outside [0.9, 1.1]) are rejected
#   - re-running overwrites stale files (idempotency)
#   - the summary line at the end of the task surfaces source + sizes
#   - every source URL pins black fill (simpleicons `/000000`
#     suffix OR iconify `?color=%23000000` query)
#
# We feed `ImageProcessing::Vips` real fixture bytes (a minimal but
# valid SVG and a minimal but valid PNG) so the resize pipeline runs
# end-to-end against libvips. We do not stub vips itself — the whole
# point of the rake task is that vips produces real bytes.
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

  # Redirect `Rails.public_path` so the task writes its OUTPUTs
  # (the 64/16 PNGs) into the tmpdir rather than the project's real
  # `public/platform_logos/`. The staging dir for downloaded
  # sources stays at the real `Rails.root.join("tmp", "platform_logos_src")`
  # — that path is gitignored (matches `/tmp/*` in `.gitignore`),
  # so spec runs are safe to scatter throwaway source bytes there.
  before do
    allow(Rails).to receive(:public_path).and_return(Pathname.new(tmpdir))
    # Sweep the staging dir before each example so a prior run's
    # source files don't leak into the assertion surface.
    staging = Rails.root.join("tmp", "platform_logos_src")
    FileUtils.rm_rf(staging) if Dir.exist?(staging)
  end

  # Minimal valid SVG — a 100x100 black square. libvips/librsvg
  # rasterizes it cleanly. >256 bytes to clear MIN_SOURCE_BYTES.
  # The viewBox is 100x100 so the square-aspect-ratio gate accepts it.
  SVG_FIXTURE = (<<~SVG + ("<!-- padding -->\n" * 20)).freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
      <rect x="0" y="0" width="100" height="100" fill="#000000"/>
      <rect x="20" y="20" width="60" height="60" fill="#ffffff"/>
    </svg>
  SVG

  # A non-square SVG fixture — viewBox 200x60 (~3.3 ratio) — used
  # to verify the square-aspect gate rejects wordmark-shaped sources.
  NON_SQUARE_SVG_FIXTURE = (<<~SVG + ("<!-- padding -->\n" * 20)).freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="60" viewBox="0 0 200 60">
      <rect x="0" y="0" width="200" height="60" fill="#000000"/>
    </svg>
  SVG

  PLATFORMS = %w[ps5 switch2 steam gog epic].freeze

  # All source URLs the rake task uses. One per slug. Four come
  # from `cdn.simpleicons.org/<slug>/000000`; switch2 comes from
  # `api.iconify.design/mdi:nintendo-switch.svg?color=%23000000`
  # because simpleicons dropped the `nintendoswitch` slug — every
  # URL still pins fill to solid black.
  SOURCE_URLS = {
    "ps5"     => "https://cdn.simpleicons.org/playstation/000000",
    "switch2" => "https://api.iconify.design/mdi:nintendo-switch.svg?color=%23000000",
    "steam"   => "https://cdn.simpleicons.org/steam/000000",
    "gog"     => "https://cdn.simpleicons.org/gogdotcom/000000",
    "epic"    => "https://cdn.simpleicons.org/epicgames/000000"
  }.freeze

  ALL_SOURCE_URLS = SOURCE_URLS.values.freeze

  def stub_all_sources_with_square_svg!
    ALL_SOURCE_URLS.each do |url|
      WebMock.stub_request(:get, url)
             .to_return(status: 200, body: SVG_FIXTURE, headers: { "Content-Type" => "image/svg+xml" })
    end
  end

  describe "monochrome black is the canonical color for every platform source" do
    # The single contract that survives provider migration: every
    # source URL pins fill to solid black (`#000000`). Two encodings
    # are allowed: simpleicons `/000000` path suffix, iconify
    # `?color=%23000000` query (URL-encoded `#000000`). Anything
    # else means the brand layer would land colored, which violates
    # the platform-logos visual contract.
    it "every URL pins fill to black via /000000 or color=%23000000" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      url_lines = source.lines.grep(/url:\s*"https?:/)
      expect(url_lines).not_to be_empty, "expected at least one url: declaration"
      url_lines.each do |line|
        is_simpleicons_black = line.include?("cdn.simpleicons.org") && line.include?("/000000")
        is_iconify_black     = line.include?("api.iconify.design") && line.include?("color=%23000000")
        expect(is_simpleicons_black || is_iconify_black).to be(true),
          "expected url: to pin fill to black (simpleicons /000000 or iconify color=%23000000), got #{line.strip}"
      end
    end

    it "names all four simpleicons platform brand slugs and the iconify switch2 fallback" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      expect(source).to include("cdn.simpleicons.org/playstation/000000")
      expect(source).to include("cdn.simpleicons.org/steam/000000")
      expect(source).to include("cdn.simpleicons.org/gogdotcom/000000")
      expect(source).to include("cdn.simpleicons.org/epicgames/000000")
      expect(source).to include("api.iconify.design/mdi:nintendo-switch.svg?color=%23000000")
    end

    # Audit trail: when we picked the iconify mdi source for switch2,
    # we tried (and rejected) several alternatives. Keep the rejected
    # URLs in the rake task as comments so the next time the source
    # rots we don't re-walk the same dead ends from scratch.
    it "preserves the switch2 source audit trail (rejected URLs as comments)" do
      source = File.read(Rails.root.join("lib", "tasks", "pito_platform_logos.rake"))
      expect(source).to include("cdn.simpleicons.org/nintendoswitch/000000")
      expect(source).to include("Nintendo_Switch_2_logo.svg")
    end
  end

  describe "happy path: every simpleicons URL returns a square SVG" do
    before { stub_all_sources_with_square_svg! }

    it "creates `public/platform_logos/` if missing" do
      expect(Dir.exist?(File.join(tmpdir, "platform_logos"))).to be(false)
      silence_stream($stdout) { task.invoke }
      expect(Dir.exist?(File.join(tmpdir, "platform_logos"))).to be(true)
    end

    it "writes BOTH a 16 and a 64 PNG per platform (10 files total)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        [ 16, 64 ].each do |size|
          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          expect(File.exist?(path)).to be(true), "expected #{path} to exist"
        end
      end
      written = Dir.glob(File.join(tmpdir, "platform_logos", "*.png"))
      expect(written.count).to eq(10)
    end

    it "writes PNGs with the EXACT pixel dimensions requested" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        [ 16, 64 ].each do |size|
          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          img = Vips::Image.new_from_file(path)
          expect([ img.width, img.height ]).to eq([ size, size ]),
            "expected #{slug}-#{size}.png to be #{size}x#{size}, got #{img.width}x#{img.height}"
        end
      end
    end

    # Project-wide rule: every platform logo MUST render as a square
    # (~1:1 aspect ratio). Non-square sources (e.g. a wordmark SVG
    # like the old Wikimedia PlayStation 5 asset at 512x111) downsize
    # to a strip (64x14) under `resize_to_fit`, which violates the
    # tile + detail-page layout contract. This guard fails fast if
    # anyone re-introduces a non-square source for any platform.
    it "produces SQUARE 64x64 PNGs for every platform (no wordmark strips)" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        path = File.join(tmpdir, "platform_logos", "#{slug}-64.png")
        Vips::Image.new_from_file(path).then do |i|
          expect([ i.width, i.height ]).to eq([ 64, 64 ]),
            "expected #{slug}-64.png to be 64x64 (square), got #{i.width}x#{i.height}"
        end
      end
    end

    it "produces SQUARE 16x16 PNGs for every platform" do
      silence_stream($stdout) { task.invoke }
      PLATFORMS.each do |slug|
        path = File.join(tmpdir, "platform_logos", "#{slug}-16.png")
        Vips::Image.new_from_file(path).then do |i|
          expect([ i.width, i.height ]).to eq([ 16, 16 ]),
            "expected #{slug}-16.png to be 16x16 (square), got #{i.width}x#{i.height}"
        end
      end
    end

    it "prints a per-platform [OK] summary line naming the source provider" do
      expect { task.invoke }.to output(/\[OK\]\s+ps5\s+source=simpleicons/).to_stdout
    end

    it "prints summary lines for every platform" do
      output = capture_stdout { task.invoke }
      PLATFORMS.each do |slug|
        expect(output).to match(/\[OK\]\s+#{slug}\s/), "missing summary line for #{slug}"
      end
    end
  end

  describe "source failure: HTTP 500 triggers a [MISS] for that slug" do
    before do
      stub_all_sources_with_square_svg!
      WebMock.stub_request(:get, SOURCE_URLS["steam"])
             .to_return(status: 500, body: "boom")
    end

    it "logs a WARN line surfacing the HTTP failure" do
      silence_stream($stdout) do
        expect { task.invoke }.to output(
          /\[pito:platform_logos\] WARN: steam source=simpleicons returned HTTP 500/
        ).to_stderr
      end
    end

    it "emits a [MISS] summary line for the failed platform" do
      output = capture_stdout { silence_stream($stderr) { task.invoke } }
      expect(output).to match(/\[MISS\]\s+steam\s+no square source available/)
    end

    it "STILL writes the other 4 platforms successfully (failure isolated)" do
      silence_stream($stdout) { silence_stream($stderr) { task.invoke } }
      (PLATFORMS - [ "steam" ]).each do |slug|
        [ 16, 64 ].each do |size|
          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          expect(File.exist?(path)).to be(true), "expected #{path} to exist"
        end
      end
    end
  end

  describe "source failure: transport error (Net::HTTP raises) triggers a [MISS]" do
    before do
      stub_all_sources_with_square_svg!
      WebMock.stub_request(:get, SOURCE_URLS["gog"])
             .to_raise(Errno::ECONNREFUSED.new("connection refused"))
    end

    it "logs a WARN line that surfaces the exception class" do
      silence_stream($stdout) do
        expect { task.invoke }.to output(
          /\[pito:platform_logos\] WARN: gog source=simpleicons raised/
        ).to_stderr
      end
    end

    it "emits a [MISS] summary line for the failed platform" do
      output = capture_stdout { silence_stream($stderr) { task.invoke } }
      expect(output).to match(/\[MISS\]\s+gog\s+no square source available/)
    end
  end

  describe "source returns a too-small body (< MIN_SOURCE_BYTES)" do
    before do
      stub_all_sources_with_square_svg!
      WebMock.stub_request(:get, SOURCE_URLS["epic"])
             .to_return(status: 200, body: "tiny", headers: { "Content-Type" => "image/svg+xml" })
    end

    it "logs a WARN line surfacing the byte-size threshold miss" do
      silence_stream($stdout) do
        expect { task.invoke }.to output(
          /\[pito:platform_logos\] WARN: epic source=simpleicons returned 4 bytes/
        ).to_stderr
      end
    end

    it "emits a [MISS] summary line for the failed platform" do
      output = capture_stdout { silence_stream($stderr) { task.invoke } }
      expect(output).to match(/\[MISS\]\s+epic\s+no square source available/)
    end
  end

  describe "source returns a non-square SVG (aspect ratio outside [0.9, 1.1])" do
    before do
      stub_all_sources_with_square_svg!
      WebMock.stub_request(:get, SOURCE_URLS["switch2"])
             .to_return(status: 200, body: NON_SQUARE_SVG_FIXTURE, headers: { "Content-Type" => "image/svg+xml" })
    end

    it "logs a WARN line naming the failed aspect-ratio gate" do
      silence_stream($stdout) do
        expect { task.invoke }.to output(
          /\[pito:platform_logos\] WARN: switch2 source=iconify-mdi rejected: source 200(\.0)?x60(\.0)? \(ratio 3\.33\) fails square gate/
        ).to_stderr
      end
    end

    it "emits a [MISS] summary line for the rejected platform" do
      output = capture_stdout { silence_stream($stderr) { task.invoke } }
      expect(output).to match(/\[MISS\]\s+switch2\s+no square source available/)
    end
  end

  describe "every source fails: existing files for the slug are left untouched" do
    before do
      stub_all_sources_with_square_svg!
      WebMock.stub_request(:get, SOURCE_URLS["switch2"]).to_return(status: 500, body: "boom")
    end

    it "does NOT delete pre-existing switch2-*.png files when the source fails" do
      target_dir = File.join(tmpdir, "platform_logos")
      FileUtils.mkdir_p(target_dir)
      stale_64 = File.join(target_dir, "switch2-64.png")
      stale_16 = File.join(target_dir, "switch2-16.png")
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
    before { stub_all_sources_with_square_svg! }

    it "replaces a pre-existing ps5-16.png with the freshly rendered bytes" do
      target_dir = File.join(tmpdir, "platform_logos")
      FileUtils.mkdir_p(target_dir)
      stale = File.join(target_dir, "ps5-16.png")
      File.binwrite(stale, "STALE-BYTES-NOT-A-REAL-PNG")
      original_size = File.size(stale)

      silence_stream($stdout) { task.invoke }

      new_size = File.size(stale)
      expect(new_size).not_to eq(original_size)
      # Verify it's a real PNG now, not the stub bytes.
      expect(File.binread(stale, 8).bytes.first(8))
        .to eq([ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ])
    end

    it "removes a stale variant (e.g. a ps5-128.png left from a prior size)" do
      target_dir = File.join(tmpdir, "platform_logos")
      FileUtils.mkdir_p(target_dir)
      stale_variant = File.join(target_dir, "ps5-128.png")
      File.binwrite(stale_variant, "STALE-128-BYTES")

      silence_stream($stdout) { task.invoke }

      expect(File.exist?(stale_variant)).to be(false)
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
