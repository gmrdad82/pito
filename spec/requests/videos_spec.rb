require "rails_helper"

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

    it "shows empty state when no videos" do
      get videos_path
      expect(response.body).to include("no videos yet")
    end

    it "does not render the legacy [bulk] toggle (always-on checkboxes)" do
      get videos_path
      # Phase B polish (2026-05-05) — checkboxes are always on; the
      # `[bulk]` enter / `[cancel]` exit toggles are gone.
      expect(response.body).not_to match(/\[\s*<span class="bl">bulk<\/span>\s*\]/)
      expect(response.body).not_to include('data-bulk-select-target="bulkToggle"')
    end

    context "with videos" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel, published_at: 1.day.ago, duration_seconds: 600) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "displays the video table" do
        get videos_path
        expect(response.body).to include(video.title)
        # Channel column now uses server-side middle-truncation: the
        # link text is `https://…<tail>`. The full channel URL still
        # appears in the cell `title` attribute and the link's `href`,
        # so asserting via `include` against the full URL is reliable.
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("500")
      end

      # Phase 4 post-Wave-3K polish — the legacy `[o]` open-action column
      # was dropped from the row. The Name cell IS the show-page link,
      # making a separate `[o]` cell redundant. Asserting absence here so
      # the column doesn't sneak back in via stray markup.
      it "no longer ships a separate [o] open-action column" do
        get videos_path
        expect(response.body).not_to include('class="bl">o</span>')
      end

      # Phase 4 Wave 3 — name column. Placeholder for the YouTube video
      # title once sync lands. The cell currently renders `video.id` as a
      # link to the show page so the column has stable content. Header is
      # a server-side sort link (`?sort=id&dir=<asc|desc>`), aligning with
      # the `/projects` index pattern. Header text was lowercased from
      # `Name` to `name` in the 2026-05-06 polish-2 pass to match the
      # rest of the design-system column labels.
      it "renders a lowercase `name` column header at column 2 (after the checkbox)" do
        get videos_path
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        ths = Nokogiri::HTML.fragment(thead).css("th")
        # Column 1 is the select-all checkbox; column 2 must be `name`.
        expect(ths[1].text.strip).to eq("name")
      end

      it "renders the name header as a server-side sort link with sort + dir params" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link).not_to be_nil
        # Default state is `published_at desc`, so clicking name should
        # request `id asc`.
        expect(link["href"]).to include("sort=id")
        expect(link["href"]).to include("dir=asc")
        expect(link.to_html).not_to include("click->sortable-table#sort")
      end

      it "renders the name cell as a link to the video show page" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        # Column index 1 (0-based) — second <td>, after the checkbox cell.
        name_cell = row.css("td")[1]
        link = name_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(video_path(video))
        expect(link.text.strip).to eq(video.id.to_s)
      end

      # Turbo Frames bugfix (2026-05-06) — the video id link sits
      # INSIDE `<turbo-frame id='videos-index-table'>` but the show
      # page has no matching frame. Stamp `data-turbo-frame=_top` so
      # the click escapes the frame and does a full-page navigation.
      it "stamps data-turbo-frame=_top on the video name link (escape the frame on row click)" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        name_cell = row.css("td")[1]
        link = name_cell.css("a").first
        expect(link["data-turbo-frame"]).to eq("_top")
      end

      it "exposes `id` in VideosController::ALLOWED_SORTS so server-side sort honors it" do
        expect(VideosController::ALLOWED_SORTS).to include("id" => "videos.id")
      end

      it "includes [+] link in table header" do
        get videos_path
        expect(response.body).to include('class="bl">+</span>')
      end

      it "shows duration" do
        get videos_path
        expect(response.body).to include("10:00")
      end

      it "renders always-on bulk select checkboxes (no hidden bulkCol)" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
        # Phase B polish (2026-05-05) — the bulkCol td/th targets are not
        # hidden anymore (they were hidden behind the [bulk] toggle).
        expect(response.body).not_to match(/data-bulk-select-target="bulkCol"\s+hidden/)
      end

      it "renders the channel-URL cell as an external YouTube link with target=_blank" do
        get videos_path
        # The channel-URL text is now the external link itself. Asserting
        # via Nokogiri instead of attribute order — `link_to` doesn't
        # guarantee any particular attribute ordering, and post-
        # consolidation the helper signature changed which reordered
        # them in the rendered output.
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("a").find { |a| a["href"] == channel.channel_url && a["target"] == "_blank" }
        expect(link).not_to be_nil
        expect(link["rel"]).to eq("noopener noreferrer")
      end

      # Post-consolidation — channel column middle-truncation. Returns
      # a single fixed-length string `<head>…<tail>` (e.g.
      # `https://…jF7eS8r1`) so the unique channel ID at the end of
      # `https://www.youtube.com/channel/<id>` stays visible. The
      # `<td>` carries the full URL via `title=` for hover-reveal.
      # Same shape as the `/channels` URL column and the footage
      # filename column.
      it "renders the channel-URL cell as a single truncated text node with a title attribute" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        # Cells: checkbox / Name / title / channel / views / ...
        # — channel column is index 3.
        channel_cell = row.css("td")[3]
        expect(channel_cell["title"]).to eq(channel.channel_url)
        link = channel_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(channel.channel_url)
        expect(link["target"]).to eq("_blank")
        expect(link["rel"]).to eq("noopener noreferrer")
        # The link's text is the head/tail string with a U+2026
        # ellipsis joining them.
        expect(link.text).to start_with("https://")
        expect(link.text).to include("…")
        expect(link.text.length).to eq(8 + 1 + 8) # head + ellipsis + tail
        expect(link.text).to end_with(channel.channel_url[-8..])
        # No two-span flex markup left over from the prior pattern.
        expect(channel_cell.css(".middle-truncate-head")).to be_empty
        expect(channel_cell.css(".middle-truncate-tail")).to be_empty
      end

      it "renders bulk actions bar (hidden by default)" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="actions"')
        expect(response.body).to include("delete")
      end

      it "passes max_panes value to bulk-select controller" do
        get videos_path
        expect(response.body).to include('data-bulk-select-max-panes-value="3"')
      end

      it "renders the panes-specific openHint and openAction targets (regression for panes-optional refactor)" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="openHint"')
        expect(response.body).to include('data-bulk-select-target="openAction"')
        expect(response.body).to include('data-bulk-select-panes-path-value="/videos/panes"')
      end

      it "renders the universal count target alongside the panes-specific targets" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="count"')
      end

      # Phase B — leading-separator pattern. Each `.action` span carries
      # its own `.action-sep` dot; the JS controller hides the dot on
      # whichever action is first-visible, so the toolbar never starts
      # with a dangling `· [ cancel ]`.
      it "renders the bulk-toolbar leading-separator pattern" do
        get videos_path
        expect(response.body).to include("bulk-toolbar")
        expect(response.body).to match(/<span class="action-sep" hidden>/)
      end

      it "ships with every leading separator hidden in the static initial render" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container in markup"
        separators = actions.css(".action-sep")
        expect(separators).not_to be_empty, "expected at least one .action-sep dot inside the toolbar"
        separators.each do |sep|
          expect(sep["hidden"]).not_to be_nil,
            "expected .action-sep to ship with the `hidden` attribute, got: #{sep.to_html}"
        end
      end
    end

    # Phase 4 Wave 3 — server-side sort via `?sort=<key>&dir=<asc|desc>`.
    # Replaces the client-side Stimulus `sortable-table` controller for
    # the index view (the controller still serves the per-pane tables).
    # Mirrors `/projects` URL-state sort.
    context "URL-state sort" do
      let!(:channel) { create(:channel) }
      let!(:older_video) do
        create(:video, channel: channel, title: "Aardvark",
               published_at: 5.days.ago)
      end
      let!(:newer_video) do
        create(:video, channel: channel, title: "Zebra",
               published_at: 1.day.ago)
      end

      it "defaults to published_at DESC (most recent first)" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        # Tbody rows are in current sort order; the title cell is the 3rd td
        # (index 2) — col 0 = checkbox, col 1 = Name, col 2 = title.
        titles = html.css("tbody tr").map { |tr| tr.css("td")[2]&.text&.strip }.compact
        expect(titles.first).to eq("Zebra")
        expect(titles.last).to eq("Aardvark")
      end

      it "sorts by title ASC when called with ?sort=title&dir=asc" do
        get videos_path, params: { sort: "title", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = html.css("tbody tr").map { |tr| tr.css("td")[2]&.text&.strip }.compact
        expect(titles).to eq([ "Aardvark", "Zebra" ])
      end

      it "sorts by title DESC when called with ?sort=title&dir=desc" do
        get videos_path, params: { sort: "title", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = html.css("tbody tr").map { |tr| tr.css("td")[2]&.text&.strip }.compact
        expect(titles).to eq([ "Zebra", "Aardvark" ])
      end

      it "sorts by id ASC when called with ?sort=id&dir=asc" do
        get videos_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        # Name column (index 1) — links contain the id text.
        ids = html.css("tbody tr").map { |tr| tr.css("td")[1].text.strip }
        expect(ids).to eq(ids.sort_by(&:to_i))
      end

      # Polish-2 (2026-05-06) — active-column indicator now rendered via
      # CSS `::after` on the parent `<th>`, driven by the `sort-asc` /
      # `sort-desc` class on the inner `<a>`. The link text is just the
      # bare label.
      it "stamps a `sort-desc` class on the active column link when dir=desc" do
        get videos_path, params: { sort: "title", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "title" }
        expect(link["class"].to_s.split).to include("sort-desc")
      end

      it "stamps a `sort-asc` class on the active column link when dir=asc" do
        get videos_path, params: { sort: "title", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "title" }
        expect(link["class"].to_s.split).to include("sort-asc")
      end

      it "renders sort links for name / title / date headers" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        links = html.css("thead a").map { |a| a.text.strip }
        # `Name` was lowercased to `name` in the 2026-05-06 polish-2 pass
        # to match the rest of Pito's column-label convention.
        expect(links).to include("name", "title", "date")
      end

      it "leaves aggregate columns (views / trend / likes / chats / watch / state / length) as plain headers" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        thead = html.css("thead")
        # No <a> wrapping the aggregate column labels.
        %w[views trend likes chats watch state length].each do |label|
          th = thead.css("th").find { |t| t.text.strip == label }
          expect(th).not_to be_nil, "expected a <th> for #{label}"
          expect(th.css("a")).to be_empty, "did not expect a sort link inside the #{label} header"
        end
      end

      it "leaves the channel column as a plain header (not sortable)" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        th = html.css("thead th").find { |t| t.text.strip == "channel" }
        expect(th).not_to be_nil
        expect(th.css("a")).to be_empty
      end

      it "ignores unknown sort keys and falls back to published_at" do
        get videos_path, params: { sort: "drop_table_videos", dir: "asc" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        # Default fallback is published_at + caller's `dir=asc`. Older first
        # under ASC.
        titles = html.css("tbody tr").map { |tr| tr.css("td")[2]&.text&.strip }.compact
        expect(titles.first).to eq("Aardvark")
      end

      it "ignores unknown dir values and falls back to desc" do
        get videos_path, params: { sort: "title", dir: "sideways" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        titles = html.css("tbody tr").map { |tr| tr.css("td")[2]&.text&.strip }.compact
        # title desc → Zebra first.
        expect(titles).to eq([ "Zebra", "Aardvark" ])
      end

      it "toggles direction when the same column is clicked twice" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("title") }
        # Default state is published_at desc — title link should request asc.
        expect(link["href"]).to include("dir=asc")

        get videos_path, params: { sort: "title", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(link["href"]).to include("dir=desc")
      end
    end

    # Polish-3 (2026-05-06) — Turbo Frame wrapper around the videos
    # table. Sort-header clicks target this frame so only the table
    # re-renders on the page (combined with `data-turbo-action=advance`
    # so the URL still updates). The frame element must be present on
    # every render — even the empty state — or Turbo aborts the swap
    # and falls back to a full-page navigation.
    describe "turbo-frame wrapper" do
      it "wraps the page output in <turbo-frame id='videos-index-table'> in the empty state" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        frame = html.css("turbo-frame#videos-index-table").first
        expect(frame).not_to be_nil, "expected <turbo-frame id='videos-index-table'> on the empty state"
      end

      context "with videos" do
        let!(:channel) { create(:channel) }
        let!(:video) { create(:video, channel: channel, title: "framed", published_at: 1.day.ago, duration_seconds: 60) }

        it "wraps the page output in <turbo-frame id='videos-index-table'> with rows" do
          get videos_path
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#videos-index-table").first
          expect(frame).not_to be_nil
          # Table sits inside the frame.
          expect(frame.css("table")).not_to be_empty
        end

        it "stamps data-turbo-frame=videos-index-table on every sort link" do
          get videos_path
          html = Nokogiri::HTML.fragment(response.body)
          sort_links = html.css("turbo-frame#videos-index-table thead a")
          expect(sort_links).not_to be_empty
          sort_links.each do |a|
            expect(a["data-turbo-frame"]).to eq("videos-index-table"),
              "expected data-turbo-frame=videos-index-table on sort link #{a.text.strip.inspect}"
            expect(a["data-turbo-action"]).to eq("advance"),
              "expected data-turbo-action=advance on sort link #{a.text.strip.inspect}"
          end
        end

        # Inverse of the row-link `_top` rule: sort header clicks should
        # re-render the frame, NOT escape to a full-page navigation.
        # Regression guard against widening sort scope by accident.
        it "does NOT stamp data-turbo-frame=_top on any sort header link" do
          get videos_path
          html = Nokogiri::HTML.fragment(response.body)
          sort_links = html.css("turbo-frame#videos-index-table thead a")
          expect(sort_links).not_to be_empty
          sort_links.each do |a|
            expect(a["data-turbo-frame"]).not_to eq("_top"),
              "sort link #{a.text.strip.inspect} must stay frame-scoped, not escape to _top"
          end
        end

        # Polish (2026-05-05) — horizontal-scroll wrapper localizes the
        # scrollbar to the table region instead of the body. The
        # wrapper sits INSIDE the turbo-frame and contains the table;
        # the bulk toolbar stays OUTSIDE the wrapper so it remains
        # aligned with the leftmost column on initial render.
        it "wraps the table in a .themed-scroll-x container with overflow-x: auto inside the turbo-frame" do
          get videos_path
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#videos-index-table").first
          expect(frame).not_to be_nil
          wrapper = frame.css("div.themed-scroll-x").first
          expect(wrapper).not_to be_nil, "expected a .themed-scroll-x wrapper inside the turbo-frame"
          expect(wrapper["style"].to_s).to include("overflow-x: auto")
          expect(wrapper["style"].to_s).to include("max-width: 100%")
          # The table must live INSIDE the scroll wrapper.
          expect(wrapper.css("table")).not_to be_empty,
            "expected the videos <table> to live inside .themed-scroll-x"
        end

        it "keeps the bulk toolbar outside the .themed-scroll-x wrapper" do
          get videos_path
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#videos-index-table").first
          wrapper = frame.css("div.themed-scroll-x").first
          # The bulk toolbar (the actions container) must NOT sit
          # inside the horizontal-scroll wrapper — otherwise it would
          # scroll horizontally with the table and lose its alignment
          # with the leftmost column on initial render.
          expect(wrapper.css('[data-bulk-select-target="actions"]')).to be_empty,
            "did not expect the bulk toolbar to live inside .themed-scroll-x"
        end
      end
    end

    context "with saved views" do
      let!(:channel) { create(:channel) }
      let!(:video1) { create(:video, channel: channel) }
      let!(:video2) { create(:video, channel: channel) }
      let!(:saved_view) { create(:saved_view, kind: :videos, name: "test", url: "/videos/panes?ids=#{video1.id},#{video2.id}") }

      it "renders saved views section" do
        get videos_path
        expect(response.body).to include("saved views")
        expect(response.body).to include(video1.title)
        expect(response.body).to include(video2.title)
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }

      it "returns video list as JSON" do
        get videos_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.first).to include("id", "title", "channel_url")
      end
    end
  end

  describe "GET /videos/:id (show)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, published_at: 1.day.ago, duration_seconds: 300) }

    it "returns 200" do
      get video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "displays video detail" do
      get video_path(video)
      expect(response.body).to include(video.title)
      expect(response.body).to include(video.youtube_video_id)
    end

    it "shows breadcrumb" do
      get video_path(video)
      expect(response.body).to include("videos")
      expect(response.body).to include(video.title)
    end

    it "includes [-] delete link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include('class="bl">-</span>')
      expect(response.body).to include("/deletions")
    end

    it "includes add pane dialog when other videos exist" do
      create(:video, channel: channel)
      get video_path(video)
      expect(response.body).to include("add a video")
      expect(response.body).to include('data-controller="add-pane"')
    end

    it "returns 404 for unknown video" do
      get video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "title", "description", "stats")
    end

    # Phase B revamp (2026-05-06) — single-pane show wraps the pane in a
    # `.pane-strip` (no-wrap horizontal flex) holding a single `.pane`
    # (640px).
    it "wraps the single pane in pane-strip > pane" do
      get video_path(video)
      expect(response.body).to include('<div class="pane-strip">')
      expect(response.body).to match(/<div class="pane-strip">\s*<[^>]*class="pane[^"]*"/)
    end
  end

  describe "GET /videos/new" do
    it "returns 200" do
      get new_video_path
      expect(response).to have_http_status(:ok)
    end

    it "shows add form" do
      get new_video_path
      expect(response.body).to include("new video")
    end
  end

  describe "POST /videos" do
    let!(:channel) { create(:channel) }

    it "creates video and redirects" do
      post videos_path, params: { video: { title: "new video", channel_id: channel.id } }
      video = Video.last
      expect(response).to redirect_to(video_path(video))
      expect(video.title).to eq("new video")
      expect(video.youtube_video_id).to start_with("local_")
    end

    it "re-renders new on invalid data" do
      post videos_path, params: { video: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("couldn't create")
    end
  end

  describe "GET /videos/:id/edit" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }

    it "returns 200" do
      get edit_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "shows edit form" do
      get edit_video_path(video)
      expect(response.body).to include("edit video")
      expect(response.body).to include(video.title)
    end
  end

  describe "PATCH /videos/:id" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "old title") }

    it "updates video and redirects" do
      patch video_path(video), params: { video: { title: "new title" } }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.title).to eq("new title")
    end

    it "re-renders edit on invalid data" do
      patch video_path(video), params: { video: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /videos/:id/stats (nested stats)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:stat_today) do
      create(:video_stat, video: video, date: Date.current,
             views: 500, likes: 25, comments: 3, watch_time_minutes: 120.5)
    end
    let!(:stat_yesterday) do
      create(:video_stat, video: video, date: Date.current - 1,
             views: 200, likes: 10, comments: 1, watch_time_minutes: 60.0)
    end

    it "returns 200 with the stats array as JSON" do
      get stats_video_path(video, format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.size).to eq(2)
    end

    it "returns the per-day VideoStat shape pito-sh expects" do
      get stats_video_path(video, format: :json)
      row = response.parsed_body.first
      expect(row.keys).to match_array(%w[date views likes comments watch_time_minutes])
      expect(row["date"]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
      expect(row["views"]).to be_a(Integer)
      expect(row["likes"]).to be_a(Integer)
      expect(row["comments"]).to be_a(Integer)
      expect(row["watch_time_minutes"]).to be_a(Float)
    end

    it "orders stats most-recent-first" do
      get stats_video_path(video, format: :json)
      dates = response.parsed_body.map { |r| r["date"] }
      expect(dates).to eq(dates.sort.reverse)
    end

    it "returns 404 for an unknown video" do
      get stats_video_path(id: 99999, format: :json)
      expect(response).to have_http_status(:not_found)
    end

    it "is reachable without an authentication token" do
      get stats_video_path(video, format: :json)
      expect(response).to have_http_status(:ok)
    end

    it "redirects HTML requests to the video show page" do
      get stats_video_path(video)
      expect(response).to redirect_to(video_path(video))
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

    # Phase B revamp (2026-05-06) — multi-pane view emits N `.pane`
    # children inside a single `.pane-strip`. The global CSS handles A/B
    # alternation via `:nth-child(odd)`/`:nth-child(even)`; the view
    # itself stays markup-only and the browser paints them.
    it "renders one .pane per video inside a single .pane-strip" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      strips = response.body.scan(/class="pane-strip"/).size
      panes = response.body.scan(/class="pane(?:\s[^"]*)?"/).size
      expect(strips).to eq(1)
      expect(panes).to eq(2)
    end

    it "includes focus link per pane" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("focus")
    end

    it "includes reorder arrows" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("◀")
      expect(response.body).to include("▶")
    end

    it "includes minus link per pane" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("−")
    end

    it "handles unknown IDs gracefully" do
      get "#{panes_videos_path}?ids=#{video1.id},99999"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video1.title)
      expect(response.body).to include("video not found")
    end

    it "includes add pane dialog with available videos" do
      video3 = create(:video, channel: channel)
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("add a video")
      expect(response.body).to include(video3.title.first(20))
    end

    it "shows save button when no saved view exists" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include('class="bl">save</span>')
      expect(response.body).not_to include('class="bl">update</span>')
    end

    it "shows delete link when saved view exists" do
      url = "/videos/panes?ids=#{video1.id},#{video2.id}"
      create(:saved_view, kind: :videos, name: "test view", url: url)
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("text-danger")
    end

    it "reorder arrow swaps adjacent IDs in URL" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("ids=#{video2.id},#{video1.id}")
    end

    it "minus link on 2-pane redirects to show" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include(video_path(video2))
      expect(response.body).to include(video_path(video1))
    end
  end
end
