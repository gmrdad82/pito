require "rails_helper"

# Phase 7.5 §11e — Channel watermark preview system spec.
#
# rack_test driver — does NOT execute JavaScript. The watermark
# preview is a server-rendered Rails surface; the only dynamic
# behavior in 11e is "save the form, see the preview reflect the
# new values on reload". No live JS preview is in scope.
#
# Critical journey:
#   * Edit page renders the inline `:edit` watermark preview
#     adjacent to the watermark form fields.
#   * Caption updates after a save (each of the four timing
#     values: always, entire_video, offset_from_start,
#     offset_from_end).
#   * The 11d preview modal renders the watermark inside each of
#     its three layout panels (desktop / mobile / tv) when the
#     channel has a watermark.
#   * Empty-frames fallback: when the directory has no JPEGs, the
#     muted `[no preview frames yet]` line replaces the player.
#   * No-watermark fallback: when channel has no watermark_url,
#     the overlay is omitted in every layout panel.
RSpec.describe "Channel watermark preview", type: :system do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir) }

  before do
    driven_by(:rack_test)
    stub_const("PreviewHelper::WATERMARK_FRAMES_DIR", tmpdir)
  end

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def write_frame(name)
    File.write(tmpdir.join(name), "")
  end

  let(:channel) do
    create(:channel,
           title: "Cached Title",
           description: "Cached body.",
           watermark_url: "https://example.com/watermark.png",
           watermark_timing: "always")
  end

  describe "edit page — inline preview" do
    before { write_frame("frame-01.jpg") }

    it "renders the WatermarkPreviewComponent at :edit size adjacent to the form fields" do
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-preview.watermark-preview--edit")
      expect(page).to have_css(".watermark-player--edit")
    end

    it "renders the bottom-right overlay using channel.watermark_url" do
      visit edit_channel_path(channel)

      # The edit-form variant is the only `:edit`-size overlay; the
      # 11d modal panels render their own desktop/mobile/tv overlays.
      overlay = find(".watermark-overlay--edit", visible: :all)
      expect(overlay["src"]).to eq("https://example.com/watermark.png")
      expect(overlay["data-position"]).to eq("bottom-right")
    end

    it "renders 'Visible: always' caption for the always timing" do
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end

    it "renders 'Visible: always' caption for the entire_video timing" do
      channel.update_columns(watermark_timing: "entire_video", watermark_offset_ms: nil)
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end

    it "renders 'Visible: starts at 5s' caption after saving offset_from_start with 5000ms" do
      channel.update_columns(watermark_timing: "offset_from_start", watermark_offset_ms: 5_000)
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "Visible: starts at 5s")
    end

    it "renders 'Visible: last 15s' caption after saving offset_from_end with 15000ms" do
      channel.update_columns(watermark_timing: "offset_from_end", watermark_offset_ms: 15_000)
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "Visible: last 15s")
    end

    it "renders 'No watermark set' caption when the channel has no watermark_url" do
      channel.update_columns(watermark_url: nil)
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "No watermark set")
      expect(page).to have_no_css(".watermark-overlay", visible: :all)
    end
  end

  describe "edit page — empty-frames fallback" do
    it "renders the muted [no preview frames yet] line when the frames directory is empty" do
      # tmpdir is empty by default.
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-player--empty .watermark-empty-label",
                               text: "[no preview frames yet]")
      expect(page).to have_no_css(".watermark-controls", visible: :all)
    end

    it "still renders the caption beneath the empty-state line" do
      visit edit_channel_path(channel)

      expect(page).to have_css(".watermark-caption", text: "Visible: always")
    end
  end

  describe "11d preview modal — watermark composition" do
    before { write_frame("frame-01.jpg") }

    it "renders the watermark inside the desktop, mobile, and tv panels" do
      visit edit_channel_path(channel)

      # The 11d modal renders all three layout panels concurrently
      # (only one is visible at a time). Each panel should carry a
      # `preview-watermark--<layout>` slot when the channel has a
      # watermark.
      expect(page).to have_css("#preview-layout-desktop .preview-watermark--desktop",
                               visible: :all)
      expect(page).to have_css("#preview-layout-mobile .preview-watermark--mobile",
                               visible: :all)
      expect(page).to have_css("#preview-layout-tv .preview-watermark--tv", visible: :all)

      # Each composition emits the layout-appropriate player variant.
      expect(page).to have_css(".watermark-player--desktop", visible: :all)
      expect(page).to have_css(".watermark-player--mobile", visible: :all)
      expect(page).to have_css(".watermark-player--tv", visible: :all)
    end

    it "renders the bottom-right overlay in every layout panel" do
      visit edit_channel_path(channel)

      desktop_overlay = find("#preview-layout-desktop .watermark-overlay", visible: :all)
      mobile_overlay = find("#preview-layout-mobile .watermark-overlay", visible: :all)
      tv_overlay = find("#preview-layout-tv .watermark-overlay", visible: :all)

      [ desktop_overlay, mobile_overlay, tv_overlay ].each do |overlay|
        expect(overlay["data-position"]).to eq("bottom-right")
        expect(overlay["src"]).to eq("https://example.com/watermark.png")
      end
    end

    it "renders the watermark caption inside every layout panel" do
      channel.update_columns(watermark_timing: "offset_from_end", watermark_offset_ms: 8_000)
      visit edit_channel_path(channel)

      expect(page).to have_css("#preview-layout-desktop .watermark-caption",
                               text: "Visible: last 8s", visible: :all)
      expect(page).to have_css("#preview-layout-mobile .watermark-caption",
                               text: "Visible: last 8s", visible: :all)
      expect(page).to have_css("#preview-layout-tv .watermark-caption",
                               text: "Visible: last 8s", visible: :all)
    end

    it "omits the watermark composition entirely when the channel has no watermark_url" do
      channel.update_column(:watermark_url, nil)
      visit edit_channel_path(channel)

      # No preview-watermark slot in any of the three panels — the
      # inline edit-form preview is the only watermark-related surface
      # in that case (and it renders the No-watermark caption).
      expect(page).to have_no_css("#preview-layout-desktop .preview-watermark--desktop",
                                  visible: :all)
      expect(page).to have_no_css("#preview-layout-mobile .preview-watermark--mobile",
                                  visible: :all)
      expect(page).to have_no_css("#preview-layout-tv .preview-watermark--tv", visible: :all)
    end
  end

  describe "hard-rule hygiene" do
    before { write_frame("frame-01.jpg") }

    it "introduces no confirm/alert/data-turbo-confirm on the edit page" do
      visit edit_channel_path(channel)

      expect(page.body).not_to include("data-turbo-confirm")
      expect(page.body).not_to match(/window\.confirm\(/)
      expect(page.body).not_to match(/alert\(/)
    end
  end
end
