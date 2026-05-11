require "rails_helper"

# Phase 11 §01a — Video edit page polish. Capybara smoke for the
# thumbnail upload + chapters / end-screens nested editors.
#
# rack_test drives without JS, so the `[add chapter]` Stimulus
# controller cannot fire here. The spec exercises the server-side
# nested-attributes round-trip by submitting the form with hand-
# crafted nested params (the shape Stimulus would build) via direct
# `page.driver.submit` calls, plus rack_test-friendly form fills
# for the persisted-row paths.
RSpec.describe "Video edit polish", type: :system do
  before { driven_by(:rack_test) }

  let(:channel) { create(:channel) }
  let!(:video) { create(:video, channel: channel, title: "edit polish target") }

  describe "edit page renders the polish sub-sections" do
    it "stacks thumbnail / tags / chapters / end-screens inside the standalone pane" do
      visit edit_video_path(video)
      expect(page).to have_css("div.pane.pane--standalone")
      within("div.pane.pane--standalone") do
        expect(page).to have_content("thumbnail")
        expect(page).to have_content("tags")
        expect(page).to have_content("chapters")
        expect(page).to have_content("end screens")
        expect(page).to have_button("[add chapter]")
        expect(page).to have_button("[add end screen]")
      end
    end
  end

  describe "thumbnail upload" do
    it "attaches a PNG file and persists" do
      visit edit_video_path(video)
      # Write a tiny PNG to a temp file so rack_test can attach it.
      tmp = Tempfile.new([ "thumb", ".png" ])
      tmp.binmode
      tmp.write(VideoFactoryHelpers.png_bytes)
      tmp.flush

      attach_file("video[thumbnail]", tmp.path)
      click_button "[save changes]"

      expect(video.reload.thumbnail).to be_attached
    end
  end

  describe "tags input round-trip" do
    it "persists comma-separated tags as an array" do
      visit edit_video_path(video)
      fill_in "video_tags", with: "gaming, dev, pito"
      click_button "[save changes]"
      expect(video.reload.tags).to eq([ "gaming", "dev", "pito" ])
    end
  end

  describe "chapters — server-side submit simulating Stimulus add" do
    it "creates two chapters via nested attributes" do
      # Stimulus normally renders the new rows. Under rack_test we
      # POST directly to mirror the post-add submit shape.
      page.driver.submit :patch, video_path(video), {
        video: {
          video_chapters_attributes: {
            "0" => { start_seconds: "0", label: "intro" },
            "1" => { start_seconds: "120", label: "setup" }
          }
        }
      }
      chapters = video.reload.video_chapters.ordered.to_a
      expect(chapters.map(&:label)).to eq([ "intro", "setup" ])
    end

    it "removes a chapter via _destroy without a JS confirm" do
      chapter = create(:video_chapter, video: video, start_seconds: 0, label: "intro")
      page.driver.submit :patch, video_path(video), {
        video: {
          video_chapters_attributes: {
            "0" => { id: chapter.id.to_s, _destroy: "1" }
          }
        }
      }
      expect(video.reload.video_chapters.count).to eq(0)
    end
  end

  describe "end-screens — server-side submit simulating Stimulus add" do
    it "creates a related_video end-screen via nested attributes" do
      page.driver.submit :patch, video_path(video), {
        video: {
          video_end_screens_attributes: {
            "0" => { kind: "related_video", target_id: "yt_abc",
                     target_label: "watch next", position: "0" }
          }
        }
      }
      es = video.reload.video_end_screens.first
      expect(es).not_to be_nil
      expect(es.kind_related_video?).to be(true)
    end

    it "kind: none toggle collapses prior rows" do
      existing = create(:video_end_screen,
                        video: video,
                        kind: :related_video,
                        target_id: "yt_old",
                        position: 0)
      page.driver.submit :patch, video_path(video), {
        video: {
          video_end_screens_attributes: {
            "0" => { id: existing.id.to_s },
            "1" => { kind: "none", position: "1" }
          }
        }
      }
      rows = video.reload.video_end_screens.to_a
      expect(rows.size).to eq(1)
      expect(rows.first.kind_none?).to be(true)
    end
  end

  describe "no JS confirm dialogs in edit markup" do
    it "the edit page never embeds data-turbo-confirm or window.confirm" do
      visit edit_video_path(video)
      expect(page.html).not_to include("data-turbo-confirm")
      expect(page.html).not_to match(/window\.confirm/)
    end
  end
end
