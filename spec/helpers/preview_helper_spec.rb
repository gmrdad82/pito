require "rails_helper"

# Phase 7.5 §11d — PreviewHelper (extended in §11e).
#
# Surfaces under test:
#
#   1. `RANDOM_VIDEO_TITLES` — frozen, non-empty, no clickbait /
#      celebrity references.
#   2. `random_video_thumbnail(seed:)` — deterministic for a given
#      seed; `nil` when the directory is empty.
#   3. `random_watermark_frame(seed:)` — 11e: deterministic per-seed
#      pick from `public/preview/watermark_frames/`; `nil` when empty.
#   4. `format_watermark_timing(timing, offset_ms)` — 11e: human
#      caption for the watermark preview.
RSpec.describe PreviewHelper do
  describe "RANDOM_VIDEO_TITLES" do
    it "is frozen and non-empty" do
      expect(described_class::RANDOM_VIDEO_TITLES).to be_frozen
      expect(described_class::RANDOM_VIDEO_TITLES).not_to be_empty
    end

    it "every entry is a short, plain string" do
      described_class::RANDOM_VIDEO_TITLES.each do |title|
        expect(title).to be_a(String)
        expect(title.length).to be_between(1, 80)
      end
    end
  end

  describe ".sample_titles" do
    it "returns the requested number of titles" do
      out = described_class.sample_titles(count: 6, seed: 0)
      expect(out.size).to eq(6)
    end

    it "is deterministic for the same seed" do
      first  = described_class.sample_titles(count: 6, seed: 42)
      second = described_class.sample_titles(count: 6, seed: 42)
      expect(first).to eq(second)
    end

    it "returns an empty array when count <= 0" do
      expect(described_class.sample_titles(count: 0, seed: 0)).to eq([])
    end

    it "wraps around the pool when count exceeds the title list size" do
      pool_size = described_class::RANDOM_VIDEO_TITLES.size
      out = described_class.sample_titles(count: pool_size + 3, seed: 0)
      expect(out.size).to eq(pool_size + 3)
      expect(out.first).to eq(described_class::RANDOM_VIDEO_TITLES.first)
    end
  end

  describe ".random_video_thumbnail" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

    before { stub_const("#{described_class}::THUMBNAILS_DIR", tmpdir) }
    after  { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    it "returns nil when the directory is empty" do
      expect(described_class.random_video_thumbnail(seed: 0)).to be_nil
    end

    it "returns nil when the directory does not exist" do
      stub_const("#{described_class}::THUMBNAILS_DIR", tmpdir.join("missing"))
      expect(described_class.random_video_thumbnail(seed: 0)).to be_nil
    end

    it "returns the same path for the same seed (deterministic)" do
      %w[thumb-01.jpg thumb-02.jpg thumb-03.jpg].each do |name|
        File.write(tmpdir.join(name), "")
      end
      a = described_class.random_video_thumbnail(seed: 7)
      b = described_class.random_video_thumbnail(seed: 7)
      expect(a).to eq(b)
      expect(a).to start_with("/preview/video_thumbnails/thumb-")
    end

    it "ignores non-matching files in the directory" do
      File.write(tmpdir.join("not-a-thumb.txt"), "")
      expect(described_class.random_video_thumbnail(seed: 0)).to be_nil

      File.write(tmpdir.join("thumb-01.jpg"), "")
      expect(described_class.random_video_thumbnail(seed: 0))
        .to eq("/preview/video_thumbnails/thumb-01.jpg")
    end

    it "wraps the seed across the available files" do
      File.write(tmpdir.join("thumb-01.jpg"), "")
      File.write(tmpdir.join("thumb-02.jpg"), "")
      expect(described_class.random_video_thumbnail(seed: 0))
        .to eq("/preview/video_thumbnails/thumb-01.jpg")
      expect(described_class.random_video_thumbnail(seed: 1))
        .to eq("/preview/video_thumbnails/thumb-02.jpg")
      expect(described_class.random_video_thumbnail(seed: 2))
        .to eq("/preview/video_thumbnails/thumb-01.jpg")
    end
  end

  describe ".available_thumbnail_files" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

    before { stub_const("#{described_class}::THUMBNAILS_DIR", tmpdir) }
    after  { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    it "returns sorted basenames matching thumb-*.jpg" do
      %w[thumb-03.jpg thumb-01.jpg thumb-02.jpg not-a-thumb.png].each do |name|
        File.write(tmpdir.join(name), "")
      end
      expect(described_class.available_thumbnail_files)
        .to eq(%w[thumb-01.jpg thumb-02.jpg thumb-03.jpg])
    end

    it "returns [] when the directory is missing" do
      stub_const("#{described_class}::THUMBNAILS_DIR", tmpdir.join("missing"))
      expect(described_class.available_thumbnail_files).to eq([])
    end
  end

  describe ".random_watermark_frame" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

    before { stub_const("#{described_class}::WATERMARK_FRAMES_DIR", tmpdir) }
    after  { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    it "returns nil when the directory is empty" do
      expect(described_class.random_watermark_frame(seed: 0)).to be_nil
    end

    it "returns nil when the directory does not exist" do
      stub_const("#{described_class}::WATERMARK_FRAMES_DIR", tmpdir.join("missing"))
      expect(described_class.random_watermark_frame(seed: 0)).to be_nil
    end

    it "returns the same path for the same seed (deterministic)" do
      %w[frame-a.jpg frame-b.jpg frame-c.jpg].each do |name|
        File.write(tmpdir.join(name), "")
      end
      a = described_class.random_watermark_frame(seed: 7)
      b = described_class.random_watermark_frame(seed: 7)
      expect(a).to eq(b)
      expect(a).to start_with("/preview/watermark_frames/")
    end

    it "accepts both .jpg and .jpeg extensions" do
      File.write(tmpdir.join("alpha.jpg"), "")
      File.write(tmpdir.join("beta.jpeg"), "")
      File.write(tmpdir.join("not-a-frame.png"), "")
      File.write(tmpdir.join("readme.txt"), "")

      seen = (0..3).map { |s| described_class.random_watermark_frame(seed: s) }
      expect(seen).to all(start_with("/preview/watermark_frames/"))
      expect(seen.uniq).to match_array(%w[
        /preview/watermark_frames/alpha.jpg
        /preview/watermark_frames/beta.jpeg
      ])
    end

    it "wraps the seed across the available files" do
      File.write(tmpdir.join("aaa.jpg"), "")
      File.write(tmpdir.join("bbb.jpg"), "")
      expect(described_class.random_watermark_frame(seed: 0))
        .to eq("/preview/watermark_frames/aaa.jpg")
      expect(described_class.random_watermark_frame(seed: 1))
        .to eq("/preview/watermark_frames/bbb.jpg")
      expect(described_class.random_watermark_frame(seed: 2))
        .to eq("/preview/watermark_frames/aaa.jpg")
    end

    it "tolerates negative seeds" do
      File.write(tmpdir.join("aaa.jpg"), "")
      expect(described_class.random_watermark_frame(seed: -5))
        .to eq("/preview/watermark_frames/aaa.jpg")
    end
  end

  describe ".available_watermark_frames" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

    before { stub_const("#{described_class}::WATERMARK_FRAMES_DIR", tmpdir) }
    after  { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    it "returns sorted basenames matching the watermark glob" do
      %w[c.jpg a.jpg b.jpeg ignore.png readme.txt].each do |name|
        File.write(tmpdir.join(name), "")
      end
      expect(described_class.available_watermark_frames)
        .to eq(%w[a.jpg b.jpeg c.jpg])
    end

    it "returns [] when the directory is missing" do
      stub_const("#{described_class}::WATERMARK_FRAMES_DIR", tmpdir.join("missing"))
      expect(described_class.available_watermark_frames).to eq([])
    end
  end

  describe ".format_watermark_timing" do
    it "renders 'Visible: always' for 'always'" do
      expect(described_class.format_watermark_timing("always", nil))
        .to eq("Visible: always")
    end

    it "renders 'Visible: always' for 'entire_video'" do
      expect(described_class.format_watermark_timing("entire_video", 99_999))
        .to eq("Visible: always")
    end

    it "renders 'Visible: starts at 5s' for 'offset_from_start' with 5000ms" do
      expect(described_class.format_watermark_timing("offset_from_start", 5_000))
        .to eq("Visible: starts at 5s")
    end

    it "renders 'Visible: last 15s' for 'offset_from_end' with 15000ms" do
      expect(described_class.format_watermark_timing("offset_from_end", 15_000))
        .to eq("Visible: last 15s")
    end

    it "rounds millisecond offsets to whole seconds" do
      expect(described_class.format_watermark_timing("offset_from_start", 5_400))
        .to eq("Visible: starts at 5s")
      expect(described_class.format_watermark_timing("offset_from_start", 5_500))
        .to eq("Visible: starts at 6s")
    end

    it "renders 0s when the offset is nil for an offset variant" do
      expect(described_class.format_watermark_timing("offset_from_start", nil))
        .to eq("Visible: starts at 0s")
    end

    it "clamps negative offsets to 0s (defensive)" do
      expect(described_class.format_watermark_timing("offset_from_end", -1_000))
        .to eq("Visible: last 0s")
    end

    it "returns 'No watermark set' for nil timing" do
      expect(described_class.format_watermark_timing(nil, nil))
        .to eq("No watermark set")
    end

    it "returns 'No watermark set' for an empty-string timing" do
      expect(described_class.format_watermark_timing("", 0))
        .to eq("No watermark set")
    end

    it "returns 'No watermark set' for an unrecognized timing value" do
      expect(described_class.format_watermark_timing("bogus", 5_000))
        .to eq("No watermark set")
    end

    it "accepts symbol timing values" do
      expect(described_class.format_watermark_timing(:always, nil))
        .to eq("Visible: always")
      expect(described_class.format_watermark_timing(:offset_from_start, 3_000))
        .to eq("Visible: starts at 3s")
    end
  end
end
