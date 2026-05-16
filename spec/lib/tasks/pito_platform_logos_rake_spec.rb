require "rails_helper"
require "rake"

# Phase 27 v2 spec 07 — `pito:platform_logos:download` rake task spec.
#
# Stubs Google's favicon service for all ten fetch combinations
# (5 platforms × 2 sizes), invokes the task against a tmpdir
# `Rails.public_path`, and asserts each of the 10 PNGs lands with
# the stubbed body bytes. Also covers the partial-failure path: one
# HTTP 500 stub leaves the other 9 files intact and the task still
# exits success.
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

  # Redirect `Rails.public_path` so the task writes into the tmpdir
  # rather than the project's real `public/platform_logos/`. The
  # path itself comes from `Rails.application.paths["public"].first`
  # so any stub that returns a `Pathname` is enough.
  before do
    allow(Rails).to receive(:public_path).and_return(Pathname.new(tmpdir))
  end

  # 5 platforms × 2 sizes; the stub body for each combination is
  # `"<slug>-<size>"` so the on-disk assertion can match a unique
  # signature per file.
  EXPECTED = [
    [ "ps5",     "playstation.com" ],
    [ "switch2", "nintendo.com" ],
    [ "steam",   "steampowered.com" ],
    [ "gog",     "gog.com" ],
    [ "epic",    "epicgames.com" ]
  ].freeze

  def stub_all_logos!
    EXPECTED.each do |slug, domain|
      [ 16, 64 ].each do |size|
        WebMock.stub_request(:get, "https://www.google.com/s2/favicons?domain=#{domain}&sz=#{size}")
               .to_return(status: 200, body: "#{slug}-#{size}", headers: { "Content-Type" => "image/png" })
      end
    end
  end

  describe "happy: writes all 10 files from stubbed bytes" do
    before { stub_all_logos! }

    it "creates `public/platform_logos/` if missing" do
      expect(Dir.exist?(File.join(tmpdir, "platform_logos"))).to be(false)
      task.invoke
      expect(Dir.exist?(File.join(tmpdir, "platform_logos"))).to be(true)
    end

    it "writes one PNG per platform / size combination" do
      task.invoke
      EXPECTED.each do |slug, _|
        [ 16, 64 ].each do |size|
          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          expect(File.exist?(path)).to be(true), "expected #{path} to exist"
        end
      end
    end

    it "writes the stubbed response body bytes verbatim" do
      task.invoke
      EXPECTED.each do |slug, _|
        [ 16, 64 ].each do |size|
          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          expect(File.binread(path)).to eq("#{slug}-#{size}")
        end
      end
    end

    it "logs one `saved` line per successful download" do
      expect { task.invoke }.to output(
        /\[pito:platform_logos\] saved public\/platform_logos\/ps5-16\.png/
      ).to_stdout
    end
  end

  describe "partial failure: HTTP 500 logs a warning and continues" do
    before do
      stub_all_logos!
      # Override the steam-64 stub to return 500.
      WebMock.stub_request(:get, "https://www.google.com/s2/favicons?domain=steampowered.com&sz=64")
             .to_return(status: 500, body: "boom")
    end

    it "writes the other 9 files successfully" do
      silence_stream($stderr) { task.invoke }
      EXPECTED.each do |slug, _|
        [ 16, 64 ].each do |size|
          next if slug == "steam" && size == 64

          path = File.join(tmpdir, "platform_logos", "#{slug}-#{size}.png")
          expect(File.exist?(path)).to be(true), "expected #{path} to exist"
        end
      end
    end

    it "does NOT write the failing slug-size combination" do
      silence_stream($stderr) { task.invoke }
      path = File.join(tmpdir, "platform_logos", "steam-64.png")
      expect(File.exist?(path)).to be(false)
    end

    it "logs a WARN line for the failing fetch" do
      expect { task.invoke }.to output(
        /\[pito:platform_logos\] WARN: steam 64 fetch returned HTTP 500/
      ).to_stderr
    end

    it "exits 0 — does not raise" do
      expect { silence_stream($stderr) { task.invoke } }.not_to raise_error
    end
  end

  describe "transport error (Net::HTTP raises) logs a warning and continues" do
    before do
      stub_all_logos!
      WebMock.stub_request(:get, "https://www.google.com/s2/favicons?domain=gog.com&sz=16")
             .to_raise(Errno::ECONNREFUSED.new("connection refused"))
    end

    it "logs a WARN line that surfaces the exception class" do
      expect { task.invoke }.to output(
        /\[pito:platform_logos\] WARN: gog 16 fetch raised/
      ).to_stderr
    end

    it "writes the remaining 9 files" do
      silence_stream($stderr) { task.invoke }
      written = Dir.glob(File.join(tmpdir, "platform_logos", "*.png"))
      expect(written.count).to eq(9)
    end
  end

  describe "idempotency: re-running overwrites the local files" do
    it "replaces an existing file with the freshly fetched bytes" do
      target_dir = File.join(tmpdir, "platform_logos")
      FileUtils.mkdir_p(target_dir)
      stale = File.join(target_dir, "ps5-16.png")
      File.binwrite(stale, "STALE")

      stub_all_logos!
      task.invoke

      expect(File.binread(stale)).to eq("ps5-16")
    end
  end

  # Local helper — RSpec's deprecated-but-still-shipped silence_stream
  # is not loaded by default; this minimal shim swallows IO from
  # warn/puts so the "writes other 9 files" expectations don't
  # smear noise into the spec output.
  def silence_stream(stream)
    original = stream.dup
    stream.reopen(File.new(File::NULL, "w"))
    yield
  ensure
    stream.reopen(original) if original
  end
end
