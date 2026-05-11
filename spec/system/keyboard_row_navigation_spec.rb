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

  # 2026-05-10 — hjkl ubiquity. Detail pages bind `h` / `l` to
  # previous / next sibling record. Each show template emits the
  # URLs as `data-keyboard-detail-prev-url` / `data-keyboard-detail-next-url`
  # on a wrapping container; the global keyboard controller looks
  # them up via `document.querySelector`. These specs verify the
  # markup contract — the keystroke behaviour is exercised by hand
  # via the manual playbook.
  describe "detail-page sibling navigation markup" do
    describe "/channels/:slug" do
      let!(:channel_a) do
        create(:channel, channel_url: "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA")
      end
      let!(:channel_b) do
        create(:channel, channel_url: "https://www.youtube.com/channel/UCBBBBBBBBBBBBBBBBBBBBBB")
      end
      let!(:channel_c) do
        create(:channel, channel_url: "https://www.youtube.com/channel/UCCCCCCCCCCCCCCCCCCCCCCC")
      end

      it "emits prev + next URLs on the middle channel's show page" do
        visit "/channels/#{channel_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end

      it "omits the prev URL on the first channel's show page" do
        visit "/channels/#{channel_a.to_param}"
        expect(page).to have_no_css("[data-keyboard-detail-prev-url]")
        expect(page).to have_css("[data-keyboard-detail-next-url]")
      end

      it "omits the next URL on the last channel's show page" do
        visit "/channels/#{channel_c.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url]")
        expect(page).to have_no_css("[data-keyboard-detail-next-url]")
      end
    end

    describe "/videos/:slug" do
      let!(:channel) { create(:channel) }
      let!(:video_a) { create(:video, channel: channel) }
      let!(:video_b) { create(:video, channel: channel) }
      let!(:video_c) { create(:video, channel: channel) }

      it "emits prev + next URLs on the middle video's show page" do
        visit "/videos/#{video_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/projects/:slug" do
      let!(:project_a) { create(:project, name: "Alpha") }
      let!(:project_b) { create(:project, name: "Bravo") }
      let!(:project_c) { create(:project, name: "Charlie") }

      it "emits prev + next URLs on the middle project's show page" do
        visit "/projects/#{project_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/games/:slug" do
      let!(:game_a) { create(:game, title: "Alpha") }
      let!(:game_b) { create(:game, title: "Bravo") }
      let!(:game_c) { create(:game, title: "Charlie") }

      it "emits prev + next URLs on the middle game's show page" do
        visit "/games/#{game_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/bundles/:slug" do
      let!(:bundle_a) { create(:bundle, name: "Alpha") }
      let!(:bundle_b) { create(:bundle, name: "Bravo") }
      let!(:bundle_c) { create(:bundle, name: "Charlie") }

      it "emits prev + next URLs on the middle bundle's show page" do
        visit "/bundles/#{bundle_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/footages/:slug" do
      let!(:project) { create(:project) }
      let!(:footage_a) { create(:footage, project: project) }
      let!(:footage_b) { create(:footage, project: project) }
      let!(:footage_c) { create(:footage, project: project) }

      it "emits prev + next URLs on the middle footage's show page" do
        visit "/footages/#{footage_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/collections/:slug" do
      let!(:collection_a) { create(:collection, name: "Alpha") }
      let!(:collection_b) { create(:collection, name: "Bravo") }
      let!(:collection_c) { create(:collection, name: "Charlie") }

      it "emits prev + next URLs on the middle collection's show page" do
        visit "/collections/#{collection_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    describe "/notes/:path" do
      let!(:project) { create(:project) }
      let!(:note_a) { create(:note, project: project, path: "a.md") }
      let!(:note_b) { create(:note, project: project, path: "b.md") }
      let!(:note_c) { create(:note, project: project, path: "c.md") }
      # A note in another project must NOT appear as a sibling.
      let!(:other_project) { create(:project) }
      let!(:note_other) { create(:note, project: other_project, path: "other.md") }

      it "emits prev + next URLs scoped to the same project" do
        visit "/notes/#{note_b.to_param}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
        nav = page.find("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]", match: :first)
        # Sibling URLs must point at notes inside the same project,
        # never the cross-project note.
        expect(nav["data-keyboard-detail-prev-url"]).to eq("/notes/#{note_a.to_param}")
        expect(nav["data-keyboard-detail-next-url"]).to eq("/notes/#{note_c.to_param}")
      end
    end

    describe "/calendar/entries/:id" do
      let!(:entry_a) { create(:calendar_entry, title: "Alpha") }
      let!(:entry_b) { create(:calendar_entry, title: "Bravo") }
      let!(:entry_c) { create(:calendar_entry, title: "Charlie") }

      it "emits prev + next URLs on the middle entry's show page" do
        visit "/calendar/entries/#{entry_b.id}"
        expect(page).to have_css("[data-keyboard-detail-prev-url][data-keyboard-detail-next-url]")
      end
    end

    # Negative coverage — a single-record install renders the show page
    # with no sibling attributes so the keyboard controller's
    # `h` / `l` keystroke falls through (no Turbo navigation).
    describe "single-record surfaces" do
      it "does not emit either prev or next URL on /projects/:slug" do
        solo = create(:project, name: "Solo")
        visit "/projects/#{solo.to_param}"
        expect(page).to have_no_css("[data-keyboard-detail-prev-url]")
        expect(page).to have_no_css("[data-keyboard-detail-next-url]")
      end
    end
  end
end
