require "rails_helper"

# Phase 12 — video schema expansion + edit surface + pre-publish checklist.
# Re-introduces edit / update / publish / schedule / pre_publish_checklist
# actions on top of the post-Path-A2 thin retract.
RSpec.describe "Videos", type: :request do
  describe "GET /videos" do
    it "returns 200" do
      get videos_path
      expect(response).to have_http_status(:ok)
    end

    it "has page title" do
      get videos_path
      expect(response.body).to include("<title>videos ~ pito</title>")
    end

    # 2026-05-11 — the `no videos yet.` empty-state was dropped from
    # `/videos`: the `[import]` link in the header already routes the
    # user into the import flow, and the note previously bled through
    # underneath the open import modal (which is a turbo-frame
    # embedded in this page, not a full-page take-over). Assert the
    # note is GONE so it doesn't sneak back in.
    it "does NOT render `no videos yet.` (the empty-state note was dropped)" do
      get videos_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("no videos yet")
    end

    it "still renders the [import] link in the page header on the empty state" do
      get videos_path
      expect(response.body).to include('<span class="bl">import</span>')
    end

    context "with videos" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "displays the video table" do
        get videos_path
        expect(response.body).to include(video.youtube_video_id)
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("500")
      end

      it "renders the privacy_status column" do
        get videos_path
        expect(response.body).to include("private")
      end

      it "includes [edit] link on each row" do
        get videos_path
        expect(response.body).to include(edit_video_path(video))
      end

      it "renders the name column header as a server-side sort link" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link).not_to be_nil
        expect(link["href"]).to include("sort=id")
      end

      # 2026-05-11 copy sweep — `last sync` was renamed to `synced`
      # app-wide on display surfaces (underlying sort key stays
      # `last_synced_at`). Regression guard against reintroducing
      # the older label in the videos picker header.
      it "renders the synced column header (and not the older `last sync` label)" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        header_texts = html.css("thead a").map { |a| a.text.strip }
        expect(header_texts).to include("synced")
        expect(header_texts).not_to include("last sync")
      end

      # 2026-05-11 copy sweep — the bulk-select hint "select items to
      # act on" was dropped app-wide. Regression guard against
      # reintroducing it on the videos picker.
      it "does not render the dropped 'select items to act on' hint" do
        get videos_path
        expect(response.body).not_to include("select items to act on")
      end

      it "exposes `id` in VideosController::ALLOWED_SORTS so server-side sort honors it" do
        expect(VideosController::ALLOWED_SORTS).to include("id" => "videos.id")
      end

      it "renders always-on bulk select checkboxes" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      end

      # Frame-escape regression guard (2026-05-10). The videos table
      # sits inside `<turbo-frame id="videos-index-table">` so sortable
      # headers can partial-swap. Without `data-turbo-frame="_top"`
      # cascading on the bulk-toolbar actions container, the
      # controller-injected `[open N]` / `[delete N]` links would
      # navigate the click inside that frame — the panes workspace and
      # the deletions confirmation page are full-page surfaces with no
      # matching frame, so Turbo would render "Content missing".
      it "stamps data-turbo-frame=_top on the bulk-toolbar actions container" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container"
        expect(actions["data-turbo-frame"]).to eq("_top"),
          "bulk-toolbar must escape the videos-index-table frame so [open N] / [delete N] navigate full-page"
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel, title: "MyVideo") }

      it "returns video list as JSON in the post-12 shape" do
        get videos_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        row = json.first
        expect(row).to include(
          "id", "youtube_video_id", "channel_id", "channel_url",
          "title", "privacy_status", "published_at",
          "star", "views", "likes", "comments", "watch_time_minutes",
          "last_synced_at", "imported", "trend"
        )
      end
    end

    # Phase 21 — `?channel=<slug-or-id>` filter on the videos picker.
    # The param resolves through `Channel.friendly.find` so callers may
    # pass either the UC-id slug (canonical) or the integer id
    # (backwards-compat). Unknown values 404 — silent empty renders
    # would mask typo'd slugs as "this channel has no videos" and
    # leave the user without a recovery affordance.
    context "channel filter (?channel=<slug-or-id>)" do
      let!(:channel_a) { create(:channel, title: "Channel A") }
      let!(:channel_b) { create(:channel, title: "Channel B") }
      let!(:video_a) { create(:video, channel: channel_a, title: "A-vid") }
      let!(:video_b) { create(:video, channel: channel_b, title: "B-vid") }

      it "filters by slug (channel.to_param)" do
        get videos_path, params: { channel: channel_a.to_param }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(video_a.youtube_video_id)
        expect(response.body).not_to include(video_b.youtube_video_id)
      end

      it "filters by integer id (backwards-compat)" do
        get videos_path, params: { channel: channel_b.id.to_s }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(video_b.youtube_video_id)
        expect(response.body).not_to include(video_a.youtube_video_id)
      end

      it "JSON shape filters too (the index respond_to JSON path)" do
        get videos_path(format: :json), params: { channel: channel_a.to_param }
        ids = JSON.parse(response.body).map { |row| row["youtube_video_id"] }
        expect(ids).to include(video_a.youtube_video_id)
        expect(ids).not_to include(video_b.youtube_video_id)
      end

      it "returns 404 for an unknown channel slug" do
        get videos_path, params: { channel: "UC_does_not_exist_xxxxxxxxx" }
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for an unknown channel integer id" do
        get videos_path, params: { channel: "99999" }
        expect(response).to have_http_status(:not_found)
      end

      it "ignores a blank channel param (no filter, full list)" do
        get videos_path, params: { channel: "" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(video_a.youtube_video_id)
        expect(response.body).to include(video_b.youtube_video_id)
      end

      it "renders the FilterChipComponent chip with the channel title (not raw id)" do
        get videos_path, params: { channel: channel_a.to_param }
        html = Nokogiri::HTML.fragment(response.body)
        chip = html.css("a.filter-chip").find { |a| a.text.include?("channel:") }
        expect(chip).not_to be_nil, "expected a filter-chip anchor referencing the channel filter"
        expect(chip.text).to include("channel: Channel A")
        # The chip shows as checked ([x]) since the filter is active.
        expect(chip.text).to include("[x]")
      end

      it "falls back to the slug when channel.title is blank" do
        nameless = create(:channel, title: nil)
        create(:video, channel: nameless)
        get videos_path, params: { channel: nameless.to_param }
        html = Nokogiri::HTML.fragment(response.body)
        chip = html.css("a.filter-chip").find { |a| a.text.include?("channel:") }
        expect(chip).not_to be_nil
        expect(chip.text).to include("channel: #{nameless.to_param}")
      end

      it "clear-chip href drops the channel param (preserves siblings)" do
        get videos_path, params: { channel: channel_a.to_param, sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        chip = html.css("a.filter-chip").find { |a| a.text.include?("channel:") }
        expect(chip).not_to be_nil
        href = chip["href"]
        # Toggle-off URL: the channel param is gone, other params survive.
        expect(href).not_to include("channel=")
        expect(href).to include("sort=id")
        expect(href).to include("dir=asc")
      end

      it "does NOT render the filter row when ?channel is absent" do
        get videos_path
        expect(response.body).not_to include("class=\"text-muted\">filter:")
      end

      it "sort-header links preserve the channel param" do
        get videos_path, params: { channel: channel_a.to_param }
        html = Nokogiri::HTML.fragment(response.body)
        sort_links = html.css("thead a")
        expect(sort_links).not_to be_empty
        # Every sortable header link must carry `?channel=<slug>` so a
        # column click re-sorts WITHIN the filtered view rather than
        # silently dropping back to the full table.
        sort_links.each do |link|
          expect(link["href"]).to include("channel=#{CGI.escape(channel_a.to_param)}"),
            "sort link #{link.text.inspect} dropped ?channel — href=#{link["href"]}"
        end
      end

      it "keeps the filter chip active when the chosen channel has zero videos" do
        # 2026-05-11 — the `no videos yet.` empty-state copy was
        # dropped (see the GET /videos block above). The filter chip
        # still has to render so the user can clear the filter from
        # the empty state.
        empty = create(:channel, title: "Empty")
        get videos_path, params: { channel: empty.to_param }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("no videos yet")
        expect(response.body).to include("channel: Empty")
      end

      it "combines with a star filter on the video rows (channel scope wins)" do
        # `videos` controller doesn't expose a star filter chip yet, but
        # adding one later must compose with ?channel. Smoke the URL by
        # passing an unrelated param and confirming the channel scope
        # still narrows the rows. (Guards against future filter combos
        # silently bypassing the channel where-clause.)
        get videos_path, params: { channel: channel_a.to_param, star: "yes" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(video_a.youtube_video_id)
        expect(response.body).not_to include(video_b.youtube_video_id)
      end
    end
  end

  # Keyboard-navigation opt-in (2026-05-10): each video row carries
  # `data-keyboard-row` + `data-keyboard-row-id` so the global keyboard
  # controller's `j`/`k` highlight, `space` toggle, and `D` bulk-delete
  # resolve against the row's video id. Mirrors the hook on channels,
  # projects, notifications, and schedule rows.
  describe "keyboard-row markup" do
    let!(:channel) { create(:channel) }
    let!(:video_a) { create(:video, channel: channel) }
    let!(:video_b) { create(:video, channel: channel) }

    it "tags each video row with data-keyboard-row + data-keyboard-row-id" do
      get videos_path
      html = Nokogiri::HTML.fragment(response.body)
      rows = html.css("tbody tr[data-keyboard-row]")
      expect(rows.size).to eq(2)
      ids = rows.map { |r| r["data-keyboard-row-id"] }.sort
      expect(ids).to eq([ video_a.id.to_s, video_b.id.to_s ].sort)
    end

    it "leaves the empty-state body without keyboard-row markup" do
      Video.delete_all
      get videos_path
      expect(response.body).not_to include("data-keyboard-row")
    end
  end

  describe "GET /videos/:id (show)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "ShowMe") }

    it "returns 200" do
      get video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "displays video detail" do
      get video_path(video)
      expect(response.body).to include(video.youtube_video_id)
      expect(response.body).to include("ShowMe")
    end

    it "shows breadcrumb" do
      get video_path(video)
      expect(response.body).to include("video ##{video.id}")
    end

    it "includes [-] delete link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include("/deletions/video/#{video.id}")
    end

    it "includes [e] edit link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include(edit_video_path(video))
    end

    it "returns 404 for unknown video" do
      get video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "youtube_video_id", "channel_id", "title", "stats")
    end

    context "with project linked" do
      let!(:project) { create(:project, name: "Halo Run") }
      let!(:linked_video) { create(:video, channel: channel, project: project) }

      it "renders a part-of-project link" do
        get video_path(linked_video)
        expect(response.body).to include("part of project")
        expect(response.body).to include("Halo Run")
        expect(response.body).to include(project_path(project))
      end
    end

    context "imported video" do
      let!(:imported_video) { create(:video, :imported, channel: channel) }

      it "shows the imported indicator" do
        get video_path(imported_video)
        expect(response.body).to include("imported")
      end
    end

    context "with last_sync_error" do
      let!(:err_video) { create(:video, :with_sync_error, channel: channel) }

      it "surfaces the youtube sync error" do
        get video_path(err_video)
        expect(response.body).to include("youtube sync failed")
      end
    end

    # Layout pass (2026-05-10) — the show page splits into two rows: the
    # detail pane lives in its own `.pane-row` on row 1, and the recent
    # stats section moves below into a separate `.pane-row` carrying a
    # full-width `.pane.pane--wide`. The previous side-by-side
    # `.pane-strip` layout is retired (no more horizontal-scroll
    # workspace strip on the single-record show page); stats live in
    # their own row below the main detail. Mirrors the `/games/:id`
    # row pattern.
    context "two-row layout (detail row + stats row)" do
      it "wraps the show body in two .pane-row blocks (detail first, stats second)" do
        get video_path(video)
        body = response.body
        first_idx = body.index('<div class="pane-row">')
        second_idx = body.index('<div class="pane-row">', first_idx + 1)
        expect(first_idx).not_to be_nil
        expect(second_idx).not_to be_nil
        expect(first_idx).to be < second_idx
      end

      it "no longer wraps detail + stats inside a single .pane-strip" do
        get video_path(video)
        # The previous layout placed detail and stats side-by-side inside
        # a `.pane-strip`. The show page no longer uses `.pane-strip` for
        # this surface; the strip was an artefact of the side-by-side
        # workspace pattern.
        expect(response.body).not_to include('<div class="pane-strip">')
      end

      it "renders the detail pane (`.pane`) inside the first row" do
        get video_path(video)
        body = response.body
        first_row_start = body.index('<div class="pane-row">')
        second_row_start = body.index('<div class="pane-row">', first_row_start + 1)
        first_row_body = body[first_row_start...second_row_start]
        # Detail pane is a plain `.pane` (452px workspace column).
        expect(first_row_body).to include('<div class="pane">')
        expect(first_row_body).to include("<h2>detail</h2>")
      end

      it "renders the stats pane (`.pane.pane--wide`) inside the second row, AFTER the detail row in the DOM" do
        get video_path(video)
        body = response.body
        detail_idx = body.index("<h2>detail</h2>")
        stats_pane_idx = body.index('<div class="pane pane--wide">')
        # Stats pane sits inside the second `.pane-row` and must come
        # after the detail heading in source order.
        expect(detail_idx).not_to be_nil
        expect(stats_pane_idx).not_to be_nil
        expect(stats_pane_idx).to be > detail_idx
      end

      context "with stats present" do
        before do
          create(:video_stat, video: video, date: 1.day.ago.to_date)
          create(:video_stat, video: video, date: 2.days.ago.to_date)
        end

        it "renders the recent stats heading and table inside the wide stats pane" do
          get video_path(video)
          body = response.body
          stats_pane_open = body.index('<div class="pane pane--wide">')
          stats_pane_close = body.index("</div>\n  </div>", stats_pane_open)
          stats_pane_body = body[stats_pane_open...stats_pane_close]
          expect(stats_pane_body).to include("recent stats (")
          expect(stats_pane_body).to include('data-controller="sortable-table"')
        end

        it "allows horizontal scroll on the stats table wrapper (overflow-x: auto)" do
          get video_path(video)
          # The sortable-table wrapper around the wide stats table carries
          # an inline `overflow-x: auto` so the table can scroll
          # internally without forcing the whole page horizontally.
          expect(response.body).to match(
            /<div\s+data-controller="sortable-table"[^>]*style="[^"]*overflow-x:\s*auto/
          )
        end
      end

      context "without stats" do
        it "still places the stats pane in row 2 with the empty-state copy" do
          get video_path(video)
          body = response.body
          stats_pane_idx = body.index('<div class="pane pane--wide">')
          expect(stats_pane_idx).not_to be_nil
          stats_pane_body = body[stats_pane_idx..]
          expect(stats_pane_body).to include("<h2>recent stats</h2>")
          expect(stats_pane_body).to include("no stats yet.")
        end
      end
    end
  end

  describe "GET /videos/:id/edit" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:project) { create(:project) }

    it "returns 200" do
      get edit_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "renders the writable subset of inputs" do
      get edit_video_path(video)
      expect(response.body).to include("video[title]")
      expect(response.body).to include("video[description]")
      expect(response.body).to include("video[tags_csv]")
      expect(response.body).to include("video[category_id]")
      expect(response.body).to include("video[self_declared_made_for_kids]")
      expect(response.body).to include("video[contains_synthetic_media]")
      expect(response.body).to include("video[project_id]")
    end

    it "does NOT render a privacy_status input" do
      get edit_video_path(video)
      expect(response.body).not_to match(/name="video\[privacy_status\]"/)
    end

    it "does NOT render a publish_at input on the edit form (it is a schedule-flow only field)" do
      get edit_video_path(video)
      expect(response.body).not_to match(/name="video\[publish_at\]"/)
    end

    it "renders Studio deep-links for the four Studio-only fields" do
      get edit_video_path(video)
      expect(response.body).to include(video.studio_url)
    end

    it "returns 404 for missing video" do
      get edit_video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    # 2026-05-11 form-pane sweep — the edit form sits inside
    # `.pane.pane--standalone` like every other standalone edit page.
    it "wraps the edit form in a .pane.pane--standalone" do
      get edit_video_path(video)
      html = Nokogiri::HTML.fragment(response.body)
      pane = html.at_css("div.pane.pane--standalone")
      expect(pane).not_to be_nil
      expect(pane.at_css('input[name="video[title]"]')).not_to be_nil
    end
  end

  describe "PATCH /videos/:id (update)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "old") }
    let!(:project) { create(:project, name: "P1") }

    before { VideoSyncBack.jobs.clear }

    it "updates title and redirects" do
      patch video_path(video), params: { video: { title: "new title" } }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.title).to eq("new title")
    end

    it "updates description" do
      patch video_path(video), params: { video: { description: "new desc" } }
      expect(video.reload.description).to eq("new desc")
    end

    it "updates tags from csv input" do
      patch video_path(video), params: { video: { tags_csv: "halo, speedrun" } }
      expect(video.reload.tags).to eq([ "halo", "speedrun" ])
    end

    it "updates category_id" do
      patch video_path(video), params: { video: { category_id: "22" } }
      expect(video.reload.category_id).to eq("22")
    end

    it "updates self_declared_made_for_kids" do
      patch video_path(video), params: { video: { self_declared_made_for_kids: "1" } }
      expect(video.reload.self_declared_made_for_kids).to be(true)
    end

    it "updates contains_synthetic_media" do
      patch video_path(video), params: { video: { contains_synthetic_media: "1" } }
      expect(video.reload.contains_synthetic_media).to be(true)
    end

    it "updates project_id" do
      patch video_path(video), params: { video: { project_id: project.id } }
      expect(video.reload.project_id).to eq(project.id)
    end

    it "enqueues VideoSyncBack once on title change" do
      expect {
        patch video_path(video), params: { video: { title: "new title" } }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "JSON request returns 200 with detail JSON" do
      patch video_path(video, format: :json), params: { video: { title: "json title" } }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("json title")
    end

    context "validation failures" do
      it "rejects title > 100 chars (422)" do
        patch video_path(video), params: { video: { title: "a" * 101 } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects oversized description (422)" do
        patch video_path(video), params: { video: { description: "\u{1F600}" * 1500 } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects category_id `abc` (422)" do
        patch video_path(video), params: { video: { category_id: "abc" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "404 for missing video" do
        patch video_path(id: 99999), params: { video: { title: "x" } }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "smuggling guards" do
      it "drops smuggled youtube_video_id silently" do
        patch video_path(video), params: { video: { title: "ok", youtube_video_id: "FAKE_ID" } }
        expect(video.reload.youtube_video_id).not_to eq("FAKE_ID")
      end

      it "drops smuggled channel_id silently" do
        other = create(:channel)
        patch video_path(video), params: { video: { title: "ok", channel_id: other.id } }
        expect(video.reload.channel_id).to eq(channel.id)
      end

      it "drops smuggled etag silently" do
        patch video_path(video), params: { video: { title: "ok", etag: "evil" } }
        expect(video.reload.etag).not_to eq("evil")
      end

      it "drops smuggled last_synced_at silently" do
        patch video_path(video), params: { video: { title: "ok", last_synced_at: Time.current.iso8601 } }
        expect(video.reload.last_synced_at).to be_nil
      end

      it "drops smuggled pre_publish_checked_at silently" do
        ts = Time.current.iso8601
        patch video_path(video), params: { video: { title: "ok", pre_publish_checked_at: ts } }
        expect(video.reload.pre_publish_checked_at).to be_nil
      end

      it "drops smuggled pre_publish_game_ok silently" do
        patch video_path(video), params: { video: { title: "ok", pre_publish_game_ok: "1" } }
        expect(video.reload.pre_publish_game_ok).to be(false)
      end

      it "drops smuggled made_for_kids_effective silently" do
        patch video_path(video), params: { video: { title: "ok", made_for_kids_effective: "1" } }
        expect(video.reload.made_for_kids_effective).to be(false)
      end

      it "drops smuggled last_sync_error silently" do
        patch video_path(video), params: { video: { title: "ok", last_sync_error: "evil" } }
        expect(video.reload.last_sync_error).to be_nil
      end

      # The `update` smuggle guard rejects `privacy_status` in either
      # direction. The forward direction (private → public/unlisted)
      # belongs to `:publish`; the reverse direction (public/unlisted
      # → private) belongs to the dedicated `:unpublish` action.
      # Coverage for the unpublish direction lives in the
      # `PATCH /videos/:id/unpublish` describe block below.
      it "rejects privacy_status in update params (422)" do
        patch video_path(video), params: { video: { privacy_status: "public" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects publish_at in update params (422)" do
        patch video_path(video), params: { video: { publish_at: 1.day.from_now.iso8601 } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /videos/:id/pre_publish_checklist" do
    let!(:video) { create(:video) }

    it "returns 200" do
      get pre_publish_checklist_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "renders the four-checkbox modal" do
      get pre_publish_checklist_video_path(video)
      expect(response.body).to include("pre_publish_game_ok")
      expect(response.body).to include("pre_publish_age_ok")
      expect(response.body).to include("pre_publish_paid_promotion_ok")
      expect(response.body).to include("pre_publish_end_screen_ok")
    end

    it "includes the studio deep-links" do
      get pre_publish_checklist_video_path(video)
      expect(response.body).to include(video.studio_url)
    end

    it "pre-checks boxes whose corresponding boolean is already true" do
      video.update_columns(pre_publish_game_ok: true)
      get pre_publish_checklist_video_path(video)
      # The checkbox renders with `checked` immediately before the `>`
      # closing the input tag (no other `>` between id and the closing
      # angle bracket of the same tag because attribute values escape).
      html = Nokogiri::HTML.fragment(response.body)
      checkbox = html.css('input[type="checkbox"]#video_pre_publish_game_ok').first
      expect(checkbox).not_to be_nil
      expect(checkbox.attributes["checked"]).not_to be_nil
    end

    it "supports the schedule target_action" do
      get pre_publish_checklist_video_path(video, target_action: "schedule")
      expect(response.body).to include("video[publish_at]")
      expect(response.body).to include("confirm schedule")
    end
  end

  describe "PATCH /videos/:id/publish" do
    let!(:video) { create(:video, title: "ok", category_id: "20") }
    let(:complete_params) do
      {
        pre_publish_game_ok: "yes",
        pre_publish_age_ok: "yes",
        pre_publish_paid_promotion_ok: "yes",
        pre_publish_end_screen_ok: "yes",
        target_privacy_status: "public"
      }
    end

    before { VideoSyncBack.jobs.clear }

    it "302 redirects on success with all four yes" do
      patch publish_video_path(video), params: { video: complete_params }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.privacy_public?).to be(true)
    end

    it "stamps pre_publish_checked_at" do
      patch publish_video_path(video), params: { video: complete_params }
      expect(video.reload.pre_publish_checked_at).to be_within(2.seconds).of(Time.current)
    end

    it "enqueues VideoSyncBack" do
      expect {
        patch publish_video_path(video), params: { video: complete_params }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "supports unlisted target" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "unlisted") }
      expect(video.reload.privacy_unlisted?).to be(true)
    end

    it "422 when any boolean is no" do
      patch publish_video_path(video), params: { video: complete_params.merge(pre_publish_game_ok: "no") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status missing" do
      params = complete_params.dup
      params.delete(:target_privacy_status)
      patch publish_video_path(video), params: { video: params }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status=private (illegal)" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "private") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status=scheduled (use :schedule action)" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "scheduled") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when source video is already public" do
      already_public = create(:video, :public)
      patch publish_video_path(already_public), params: { video: complete_params }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /videos/:id/schedule" do
    let!(:video) { create(:video, title: "ok", category_id: "20") }
    let(:future) { 1.day.from_now }
    let(:base_params) do
      {
        pre_publish_game_ok: "yes",
        pre_publish_age_ok: "yes",
        pre_publish_paid_promotion_ok: "yes",
        pre_publish_end_screen_ok: "yes",
        publish_at: future.iso8601
      }
    end

    before { VideoSyncBack.jobs.clear }

    it "302 redirects on success" do
      patch schedule_video_path(video), params: { video: base_params }
      expect(response).to redirect_to(video_path(video))
    end

    it "stamps pre_publish_checked_at + sets publish_at + privacy stays private" do
      patch schedule_video_path(video), params: { video: base_params }
      v = video.reload
      expect(v.pre_publish_checked_at).to be_present
      expect(v.publish_at).to be_within(2.seconds).of(future)
      expect(v.privacy_private?).to be(true)
    end

    it "enqueues VideoSyncBack" do
      expect {
        patch schedule_video_path(video), params: { video: base_params }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "422 with past publish_at" do
      patch schedule_video_path(video), params: { video: base_params.merge(publish_at: 1.day.ago.iso8601) }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when publish_at missing" do
      params = base_params.dup
      params.delete(:publish_at)
      patch schedule_video_path(video), params: { video: params }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when any boolean no" do
      patch schedule_video_path(video), params: { video: base_params.merge(pre_publish_age_ok: "no") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when source video already public" do
      already_public = create(:video, :public)
      patch schedule_video_path(already_public), params: { video: base_params }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /videos/:id/unpublish" do
    # Dedicated `public` / `unlisted` → `private` route. Going down
    # is free per Note 1 (no checklist needed), so the privacy_status
    # flip lives outside the smuggle guard's blocklist on `update`.
    let!(:channel) { create(:channel) }

    before { VideoSyncBack.jobs.clear }

    it "flips privacy_status from public → private and redirects" do
      v = create(:video, :public, channel: channel)
      patch unpublish_video_path(v)
      expect(response).to redirect_to(video_path(v))
      expect(v.reload.privacy_private?).to be(true)
    end

    it "flips privacy_status from unlisted → private" do
      v = create(:video, :unlisted, channel: channel)
      patch unpublish_video_path(v)
      expect(v.reload.privacy_private?).to be(true)
    end

    it "enqueues VideoSyncBack on the privacy flip" do
      v = create(:video, :public, channel: channel)
      expect {
        patch unpublish_video_path(v)
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "JSON request returns 200 with detail JSON" do
      v = create(:video, :public, channel: channel)
      patch unpublish_video_path(v, format: :json)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["privacy_status"]).to eq("private")
    end

    it "422 when source video is already private" do
      v = create(:video, channel: channel) # default privacy_status = :private
      patch unpublish_video_path(v)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404 for missing video" do
      patch unpublish_video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /videos/:id" do
    let!(:video) { create(:video) }

    it "deletes the video and redirects" do
      expect {
        delete video_path(video)
      }.to change(Video, :count).by(-1)
      expect(response).to redirect_to(videos_path)
    end

    it "JSON returns 204" do
      v = create(:video)
      delete video_path(v, format: :json)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /videos/panes (multi-pane)" do
    let!(:channel) { create(:channel) }
    let!(:video1) { create(:video, channel: channel) }
    let!(:video2) { create(:video, channel: channel) }

    it "redirects to show when single ID" do
      get panes_videos_path(ids: video1.id)
      expect(response).to redirect_to(video_path(video1))
    end

    it "redirects to index when no IDs" do
      get panes_videos_path(ids: "")
      expect(response).to redirect_to(videos_path)
    end

    it "renders multi-pane view with comma-separated IDs" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video1.youtube_video_id)
      expect(response.body).to include(video2.youtube_video_id)
    end
  end

  describe "GET /videos/:id/stats(.json)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 100, likes: 5, comments: 2, watch_time_minutes: 50) }

    it "returns the stats JSON in the pito-shape" do
      get stats_video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      row = json.first
      expect(row).to include("date", "views", "likes", "comments", "watch_time_minutes")
    end

    it "redirects HTML requests to the video show page" do
      get stats_video_path(video)
      expect(response).to redirect_to(video_path(video))
    end
  end

  # Phase 11 §01a — Video edit page polish. Thumbnail upload, tags
  # round-trip, chapters + end-screens nested attributes.
  describe "Phase 11 §01a — edit page polish" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }

    before { VideoSyncBack.jobs.clear }

    describe "GET /videos/:id/edit (extended)" do
      it "renders the four new sub-sections inside the pane" do
        get edit_video_path(video)
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        pane = html.at_css("div.pane.pane--standalone")
        expect(pane).not_to be_nil
        expect(pane.to_s).to include("thumbnail")
        expect(pane.to_s).to include("tags")
        expect(pane.to_s).to include("chapters")
        expect(pane.to_s).to include("end screens")
      end

      it "renders the [add chapter] bracketed link" do
        get edit_video_path(video)
        expect(response.body).to include("[add chapter]")
      end

      it "renders the [add end screen] bracketed link" do
        get edit_video_path(video)
        expect(response.body).to include("[add end screen]")
      end

      it "renders the thumbnail file input" do
        get edit_video_path(video)
        expect(response.body).to match(/name="video\[thumbnail\]"/)
      end

      it "renders persisted chapters in start_seconds order" do
        create(:video_chapter, video: video, start_seconds: 120, label: "setup")
        create(:video_chapter, video: video, start_seconds: 0, label: "intro")
        get edit_video_path(video)
        body = response.body
        intro_idx = body.index("intro")
        setup_idx = body.index("setup")
        expect(intro_idx).not_to be_nil
        expect(setup_idx).not_to be_nil
        expect(intro_idx).to be < setup_idx
      end
    end

    describe "PATCH /videos/:id (thumbnail upload)" do
      let(:png_bytes) { VideoFactoryHelpers.png_bytes }
      let(:upload) do
        Rack::Test::UploadedFile.new(
          StringIO.new(png_bytes), "image/png", original_filename: "thumb.png"
        )
      end

      it "attaches a thumbnail on update" do
        patch video_path(video), params: { video: { thumbnail: upload } }
        expect(response).to redirect_to(video_path(video))
        expect(video.reload.thumbnail).to be_attached
      end

      it "rejects a non-image content type" do
        bad = Rack::Test::UploadedFile.new(
          StringIO.new("not an image"), "text/plain", original_filename: "note.txt"
        )
        patch video_path(video), params: { video: { thumbnail: bad } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(video.reload.thumbnail).not_to be_attached
      end
    end

    describe "PATCH /videos/:id (chapters nested attributes)" do
      it "creates new chapters via nested attributes" do
        patch video_path(video), params: {
          video: {
            video_chapters_attributes: {
              "0" => { start_seconds: "0", label: "intro" },
              "1" => { start_seconds: "120", label: "setup" }
            }
          }
        }
        expect(response).to redirect_to(video_path(video))
        chapters = video.reload.video_chapters.ordered.to_a
        expect(chapters.map(&:label)).to eq([ "intro", "setup" ])
      end

      it "destroys chapters when _destroy=1" do
        chapter = create(:video_chapter, video: video, start_seconds: 0, label: "intro")
        patch video_path(video), params: {
          video: {
            video_chapters_attributes: {
              "0" => { id: chapter.id, _destroy: "1" }
            }
          }
        }
        expect(response).to redirect_to(video_path(video))
        expect(video.reload.video_chapters.count).to eq(0)
      end

      it "rejects duplicate start_seconds with 422" do
        create(:video_chapter, video: video, start_seconds: 0, label: "intro")
        patch video_path(video), params: {
          video: {
            video_chapters_attributes: {
              "0" => { start_seconds: "0", label: "duplicate" }
            }
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(video.reload.video_chapters.count).to eq(1)
      end
    end

    describe "PATCH /videos/:id (end-screens nested attributes)" do
      it "creates a related_video end-screen via nested attributes" do
        patch video_path(video), params: {
          video: {
            video_end_screens_attributes: {
              "0" => { kind: "related_video", target_id: "yt_abc",
                       target_label: "watch next", position: "0" }
            }
          }
        }
        expect(response).to redirect_to(video_path(video))
        es = video.reload.video_end_screens.first
        expect(es).not_to be_nil
        expect(es.kind_related_video?).to be(true)
        expect(es.target_id).to eq("yt_abc")
      end

      it "collapses non-none rows when a none row is submitted" do
        existing = create(:video_end_screen,
                          video: video,
                          kind: :related_video,
                          target_id: "yt_old",
                          position: 0)
        patch video_path(video), params: {
          video: {
            video_end_screens_attributes: {
              "0" => { id: existing.id },
              "1" => { kind: "none", position: 1 }
            }
          }
        }
        expect(response).to redirect_to(video_path(video))
        rows = video.reload.video_end_screens.to_a
        expect(rows.size).to eq(1)
        expect(rows.first.kind_none?).to be(true)
      end

      it "rejects a 5th non-none row with 422" do
        4.times do |i|
          create(:video_end_screen,
                 video: video,
                 kind: :related_video,
                 target_id: "yt#{i}",
                 position: i)
        end
        patch video_path(video), params: {
          video: {
            video_end_screens_attributes: {
              "0" => { kind: "related_video", target_id: "yt5",
                       target_label: "fifth", position: "5" }
            }
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(video.reload.video_end_screens.count).to eq(4)
      end
    end

    describe "no JS confirm tokens in edit markup" do
      it "does not include data-turbo-confirm" do
        get edit_video_path(video)
        expect(response.body).not_to include("data-turbo-confirm")
      end

      it "does not include window.confirm calls" do
        get edit_video_path(video)
        expect(response.body).not_to match(/window\.confirm/)
      end
    end

    describe "friendly URL preserved" do
      it "edit route uses the youtube_video_id slug" do
        get edit_video_path(video)
        expect(response).to have_http_status(:ok)
        expect(edit_video_path(video)).to include(video.youtube_video_id)
      end
    end
  end
end
