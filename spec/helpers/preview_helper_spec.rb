require "rails_helper"

# Phase 7.5 §11d — PreviewHelper.
#
# The helper owns the static-thumbnail fallback fixtures the
# `ChannelPreviewComponent` falls back to when a channel doesn't
# have ≥6 titled real videos yet. Three surfaces under test:
#
#   1. `RANDOM_VIDEO_TITLES` — frozen, non-empty, no clickbait /
#      celebrity references.
#   2. `random_video_thumbnail(seed:)` — deterministic for a given
#      seed; `nil` when the directory is empty.
#   3. `random_watermark_frame(seed:)` — present as a stub for 11e;
#      returns `nil` (11d does not call this).
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
    # 11d does NOT call this; the stub exists so 11e can land
    # without re-opening this file. Returning nil is the
    # contractually-stable placeholder.
    it "returns nil regardless of seed (placeholder for 11e)" do
      expect(described_class.random_watermark_frame(seed: 0)).to be_nil
      expect(described_class.random_watermark_frame(seed: 42)).to be_nil
    end
  end
end
