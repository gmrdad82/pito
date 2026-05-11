require "rails_helper"

# Phase 7.5 §11e — WatermarkPreviewComponent.
#
# Four `size:` variants share the same markup (background frame +
# faux controls + overlay + caption); the variant only swaps CSS
# classes. The component is layout-agnostic; the parent picks the
# size and timing/offset values.
#
# Branch coverage:
#   * Each `size:` value renders the appropriate variant classes.
#   * Watermark overlay positioned at bottom-right via the
#     `data-position` attribute (locked Q1).
#   * Caption matches each timing+offset combo via
#     `PreviewHelper.format_watermark_timing`.
#   * Empty-frames-directory fallback renders the muted
#     `[no preview frames yet]` line.
#   * No-watermark fallback omits the overlay and renders the
#     "No watermark set" caption.
RSpec.describe WatermarkPreviewComponent, type: :component do
  # Isolate the watermark_frames directory per spec run so we don't
  # depend on what the user has dropped into `public/` on disk.
  let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

  before { stub_const("PreviewHelper::WATERMARK_FRAMES_DIR", tmpdir) }
  after  { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def write_frame(name)
    File.write(tmpdir.join(name), "")
  end

  let(:channel) do
    create(:channel,
           watermark_url: "https://example.com/watermark.png",
           watermark_timing: "always",
           watermark_offset_ms: nil)
  end

  describe "size variants" do
    before { write_frame("frame-01.jpg") }

    %i[edit desktop mobile tv].each do |size|
      it "renders the #{size} variant with the matching CSS hooks" do
        render_inline(described_class.new(channel: channel, size: size))

        expect(page).to have_css(".watermark-preview.watermark-preview--#{size}")
        expect(page).to have_css(".watermark-preview[data-size='#{size}']")
        expect(page).to have_css(".watermark-player.watermark-player--#{size}")
        expect(page).to have_css(".watermark-controls.watermark-controls--#{size}")
        expect(page).to have_css(".watermark-caption.watermark-caption--#{size}")
      end
    end

    it "defaults to :edit when size is omitted" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".watermark-preview--edit")
    end

    it "falls back to :edit when an unknown size is supplied" do
      render_inline(described_class.new(channel: channel, size: :phone))

      expect(page).to have_css(".watermark-preview--edit")
    end
  end

  describe "watermark overlay" do
    before { write_frame("frame-01.jpg") }

    it "renders the watermark image at bottom-right (data-position)" do
      render_inline(described_class.new(channel: channel, size: :desktop))

      overlay = page.find(".watermark-overlay")
      expect(overlay["src"]).to eq("https://example.com/watermark.png")
      expect(overlay["data-position"]).to eq("bottom-right")
      expect(overlay[:class]).to include("watermark-overlay--desktop")
    end

    it "renders the bottom-right overlay in every size variant" do
      %i[edit desktop mobile tv].each do |size|
        render_inline(described_class.new(channel: channel, size: size))

        expect(page).to have_css(".watermark-overlay[data-position='bottom-right']", count: 1)
      end
    end

    it "omits the overlay when channel.watermark_url is blank" do
      channel.update_column(:watermark_url, nil)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_no_css(".watermark-overlay")
    end

    it "omits the overlay when channel.watermark_url is an empty string" do
      channel.update_column(:watermark_url, "")
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_no_css(".watermark-overlay")
    end

    it "treats whitespace-only watermark_url as no watermark" do
      channel.update_column(:watermark_url, "   ")
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_no_css(".watermark-overlay")
    end
  end

  describe "caption" do
    before { write_frame("frame-01.jpg") }

    it "renders 'Visible: always' for the 'always' timing" do
      channel.update_columns(watermark_timing: "always", watermark_offset_ms: nil)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end

    it "renders 'Visible: always' for the 'entire_video' timing" do
      channel.update_columns(watermark_timing: "entire_video", watermark_offset_ms: nil)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end

    it "renders 'Visible: starts at 5s' for 'offset_from_start' with 5000ms" do
      channel.update_columns(watermark_timing: "offset_from_start",
                             watermark_offset_ms: 5_000)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: starts at 5s")
    end

    it "renders 'Visible: last 15s' for 'offset_from_end' with 15000ms" do
      channel.update_columns(watermark_timing: "offset_from_end",
                             watermark_offset_ms: 15_000)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: last 15s")
    end

    it "renders 'No watermark set' when channel has no watermark_url" do
      channel.update_columns(watermark_url: nil, watermark_timing: "always")
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "No watermark set")
    end

    it "renders 'No watermark set' when timing is nil even with a watermark_url" do
      channel.update_columns(watermark_timing: nil, watermark_offset_ms: nil)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "No watermark set")
    end

    it "honors override values from timing: / offset_ms: kwargs" do
      channel.update_columns(watermark_timing: "always", watermark_offset_ms: nil)
      render_inline(described_class.new(channel: channel, size: :edit,
                                        timing: "offset_from_end",
                                        offset_ms: 30_000))

      expect(page).to have_css(".watermark-caption", text: "Visible: last 30s")
    end

    it "renders the caption even in the empty-frames branch" do
      FileUtils.rm_rf(tmpdir)
      Dir.mkdir(tmpdir)
      channel.update_columns(watermark_timing: "always")
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end
  end

  describe "background frame" do
    it "renders the chosen frame as a background-image inline style" do
      write_frame("hero.jpg")
      render_inline(described_class.new(channel: channel, size: :desktop))

      player = page.find(".watermark-player")
      expect(player["style"]).to include("/preview/watermark_frames/hero.jpg")
    end

    it "picks the same frame deterministically for the same channel id" do
      write_frame("alpha.jpg")
      write_frame("beta.jpg")

      first = render_inline(described_class.new(channel: channel, size: :desktop))
                .css(".watermark-player").first["style"]
      second = render_inline(described_class.new(channel: channel, size: :desktop))
                 .css(".watermark-player").first["style"]
      expect(first).to eq(second)
    end

    it "honors a frame_path: override (for parent composition)" do
      write_frame("ignored.jpg")
      render_inline(described_class.new(channel: channel, size: :edit,
                                        frame_path: "/custom/path.jpg"))

      player = page.find(".watermark-player")
      expect(player["style"]).to include("/custom/path.jpg")
    end
  end

  describe "empty-frames fallback" do
    # tmpdir starts empty — no frames written.
    it "renders the muted [no preview frames yet] line in place of the player" do
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-player--empty .watermark-empty-label.text-muted",
                               text: "[no preview frames yet]")
      expect(page).to have_no_css(".watermark-controls")
      expect(page).to have_no_css(".watermark-overlay")
    end

    it "still renders the caption beneath the empty-state line" do
      channel.update_columns(watermark_timing: "offset_from_end", watermark_offset_ms: 10_000)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-caption", text: "Visible: last 10s")
    end

    it "renders no <img> overlay when frames are missing" do
      render_inline(described_class.new(channel: channel, size: :tv))

      expect(page).to have_no_css(".watermark-overlay")
    end
  end

  describe "faux player controls" do
    before { write_frame("frame-01.jpg") }

    it "renders the rough-approximation control row (play / progress / time / settings / fullscreen)" do
      render_inline(described_class.new(channel: channel, size: :desktop))

      expect(page).to have_css(".watermark-control--play")
      expect(page).to have_css(".watermark-control--progress .watermark-progress-bar")
      expect(page).to have_css(".watermark-control--time")
      expect(page).to have_css(".watermark-control--settings")
      expect(page).to have_css(".watermark-control--fullscreen")
    end
  end

  describe "hard-rule hygiene" do
    before { write_frame("frame-01.jpg") }

    it "does not introduce a JS confirm / alert / data-turbo-confirm" do
      render_inline(described_class.new(channel: channel, size: :edit))
      rendered = page.native.to_html

      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).not_to include("window.confirm")
      expect(rendered).not_to include("alert(")
      expect(rendered).not_to include("prompt(")
    end

    it "uses the no-inner-padding bracket convention for the empty-state label" do
      FileUtils.rm_rf(tmpdir)
      Dir.mkdir(tmpdir)
      render_inline(described_class.new(channel: channel, size: :edit))

      expect(page).to have_css(".watermark-empty-label", text: "[no preview frames yet]")
      expect(page).to have_no_css(".watermark-empty-label", text: "[ no preview frames yet ]")
    end
  end
end
