require "rails_helper"

# Vim-style `j`/`k` highlight navigation on list-page surfaces.
#
# The grid / tile counterpart lives in `keyboard_grid_navigation_spec.rb`
# (games, bundles, calendar month). This spec covers the row surfaces
# the j/k extension dispatch landed on (2026-05-10):
#
#   * /channels — channels table rows
#   * /videos — videos table rows
#   * /projects — projects table rows
#   * /footages — footages table rows
#   * /collections — collections table rows
#   * /notes — notes table rows
#
# rack_test does not fire JS, so these are markup-contract specs: we
# verify the data attributes the `keyboard` Stimulus controller reads
# at runtime are present in the rendered HTML. Actual `j`/`k` keystroke
# behaviour and `.keyboard-highlight` class toggling are exercised by
# hand via the manual playbook (no Selenium / cuprite driver in this
# project — see `keyboard_grid_navigation_spec.rb` for the same
# convention).
RSpec.describe "Keyboard row navigation markup", type: :system do
  before { driven_by(:rack_test) }

  describe "/channels (list rows)" do
    let!(:channel_a) do
      create(:channel, channel_url: "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA")
    end
    let!(:channel_b) do
      create(:channel, channel_url: "https://www.youtube.com/channel/UCBBBBBBBBBBBBBBBBBBBBBB")
    end

    it "tags each channel row with data-keyboard-row + data-keyboard-row-id" do
      visit "/channels"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/channels"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/videos (list rows)" do
    let!(:channel) { create(:channel) }
    let!(:video_a) { create(:video, channel: channel) }
    let!(:video_b) { create(:video, channel: channel) }

    it "tags each video row with data-keyboard-row + data-keyboard-row-id" do
      visit "/videos"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/videos"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/projects (list rows)" do
    let!(:project_a) { create(:project, name: "Alpha") }
    let!(:project_b) { create(:project, name: "Bravo") }

    it "tags each project row with data-keyboard-row + data-keyboard-row-id" do
      visit "/projects"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/projects"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/footages (list rows)" do
    let!(:project) { create(:project) }
    let!(:footage_a) { create(:footage, project: project) }
    let!(:footage_b) { create(:footage, project: project) }

    it "tags each footage row with data-keyboard-row + data-keyboard-row-id" do
      visit "/footages"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/footages"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/collections (list rows)" do
    let!(:collection_a) { create(:collection, name: "Alpha") }
    let!(:collection_b) { create(:collection, name: "Bravo") }

    it "tags each collection row with data-keyboard-row + data-keyboard-row-id" do
      visit "/collections"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/collections"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end

  describe "/notes (list rows)" do
    let!(:project) { create(:project) }
    let!(:note_a) { create(:note, project: project, title: "Alpha note") }
    let!(:note_b) { create(:note, project: project, title: "Bravo note") }

    it "tags each note row with data-keyboard-row + data-keyboard-row-id" do
      visit "/notes"
      rows = page.all("tbody tr[data-keyboard-row][data-keyboard-row-id]")
      expect(rows.size).to eq(2)
    end

    it "does NOT declare data-keyboard-grid (rows surface, not a grid)" do
      visit "/notes"
      expect(page).to have_no_css("[data-keyboard-grid]")
    end
  end
end
