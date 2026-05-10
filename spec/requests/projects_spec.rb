require "rails_helper"

RSpec.describe "Projects", type: :request do
  describe "GET /projects" do
    it "returns 200" do
      get projects_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the add bracketed link in the projects header" do
      # Site polish — `[add]` collapsed to `[+]` since the surrounding
      # `<h1>projects</h1>` already establishes the noun and the
      # site-wide bracket-link convention uses single-glyph labels.
      get projects_path
      expect(response.body).to include('class="bl">+</span>')
    end

    context "with projects" do
      let!(:project) { create(:project) }

      it "displays project names" do
        get projects_path
        expect(response.body).to include(project.name)
      end
    end

    # Phase B polish (2026-05-05) — drop the leading `[o]` action column.
    # Wave 2H made the project name itself clickable, so the dedicated open
    # link is redundant.
    describe "[o] action column removal" do
      let!(:project) { create(:project, name: "Alpha") }

      it "no longer renders an actionCol thead cell" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        # The `actionCol` target was the open-action `[o]` header. It must
        # be gone — both the thead cell and the per-row body cell.
        expect(html.css('[data-bulk-select-target="actionCol"]')).to be_empty
      end

      it "no longer renders an [o] BracketedLinkComponent inside any project row" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        # The `[o]` open link rendered as `<span class="bl">o</span>` (the
        # bracketed-link convention). Must be absent from every body row.
        expect(html.css('tbody [class="bl"]').map { |n| n.text.strip }).not_to include("o")
      end

      it "drops the table's column count by 1 (from 7 to 6 thead cells)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        # bulkCol(always-on) + name + created + footages + notes + videos = 6.
        expect(html.css("thead th").size).to eq(6)
      end

      it "keeps the project name clickable (regression — link still wraps the name cell)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("tbody tr a").find { |a| a.text.strip == "Alpha" }
        expect(link).not_to be_nil
        expect(link["href"]).to eq(project_path(project))
      end
    end

    # Phase 4 Wave 2 — `/projects` index revamp. The sortable column headers
    # mirror the URL-state pattern from `ChannelsController` (sort + dir
    # query params, sanitized through an allowlist).
    #
    # Wave 3.5+ aggregates revamp (2026-05-06): the `footages` column became
    # `footage` (singular) and renders the SUM of footage durations via
    # `human_duration`; the `notes` column header is unchanged but renders
    # the SUM of words across notes (`notes_words_total`). Sort keys
    # switched to the aggregate columns.
    describe "expanded index columns + sort" do
      let!(:project_a) { create(:project, name: "Alpha", created_at: 2.days.ago) }
      let!(:project_b) { create(:project, name: "Bravo", created_at: 1.day.ago) }

      before do
        # Hand-set the aggregate caches so the SQL ORDER BY has something to
        # discriminate on without going through the full create-footage path.
        project_a.update_columns(
          footages_count: 4, notes_count: 1, timelines_count: 0,
          footage_duration_seconds: 2058, notes_words_total: 6
        )
        project_b.update_columns(
          footages_count: 1, notes_count: 5, timelines_count: 2,
          footage_duration_seconds: 60, notes_words_total: 250
        )
      end

      it "renders the four numeric columns (created / footage / notes / videos)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        headers = html.css("thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
        # bulkCol header (empty — hosts select-all checkbox), then the five
        # data columns in order. `footage` is the new singular header.
        # Phase 12 realignment (2026-05-10): `timelines` column retired,
        # replaced with `videos` (Project.has_many :videos).
        expect(headers.last(5)).to eq([ "name", "created", "footage", "notes", "videos" ])
      end

      it "renders the project's footage duration via human_duration and notes word total" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find { |tr| tr.text.include?("Alpha") }
        expect(row).not_to be_nil
        nums = row.css("td.num").map { |td| td.text.strip }
        # First .num is the relative time string; the trailing three are
        # human_duration(footage_duration_seconds) / human_words(notes_words_total) /
        # project.videos.count. 2058s -> "34m 18s"; 6 words -> "6w" (compact
        # label with comma-delimited thousands for larger counts). Alpha has
        # no videos in this fixture, so the trailing column reads "0".
        expect(nums.last(3)).to eq([ "34m 18s", "6w", "0" ])
      end

      it "renders the project name as a link to the show page" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("tbody tr a").find { |a| a.text.strip == "Alpha" }
        expect(link).not_to be_nil
        expect(link["href"]).to eq(project_path(project_a))
      end

      # Turbo Frames bugfix (2026-05-06) — the project name link sits
      # INSIDE `<turbo-frame id='projects-index-table'>`, but it points
      # at the show page, which has no matching frame. Without
      # `data-turbo-frame=_top` Turbo would scope the navigation to the
      # frame and render "Content missing". The `_top` keyword tells
      # Turbo to navigate the whole page instead — escape the frame.
      it "stamps data-turbo-frame=_top on the project name link (escape the frame on row click)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("tbody tr a").find { |a| a.text.strip == "Alpha" }
        expect(link).not_to be_nil
        expect(link["data-turbo-frame"]).to eq("_top")
      end

      it "does NOT stamp data-turbo-frame=_top on sort header links (they stay frame-scoped)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        sort_links = html.css("turbo-frame#projects-index-table thead a")
        expect(sort_links).not_to be_empty
        sort_links.each do |a|
          expect(a["data-turbo-frame"]).not_to eq("_top"),
            "sort link #{a.text.strip.inspect} must stay frame-scoped, not escape to _top"
          expect(a["data-turbo-frame"]).to eq("projects-index-table")
        end
      end

      it "renders the created column with the compact_time_ago helper output" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find { |tr| tr.text.include?("Alpha") }
        # 2 days ago → "~2d ago"
        created_cell = row.css("td.num").first.text.strip
        expect(created_cell).to match(/\A~\d+\w+ ago\z/)
      end

      it "renders each sortable header as a link to the projects path with sort + dir params" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        # name header — clicking from the default `created_at desc` sort
        # should set sort=name dir=asc.
        name_link = html.css("thead a").find { |a| a.text.strip.start_with?("name") }
        expect(name_link).not_to be_nil
        expect(name_link["href"]).to include("sort=name")
        expect(name_link["href"]).to include("dir=asc")

        footage_link = html.css("thead a").find { |a| a.text.strip.start_with?("footage") }
        expect(footage_link).not_to be_nil
        expect(footage_link["href"]).to include("sort=footage_duration_seconds")
      end

      it "defaults to created_at DESC ordering (most recent first)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        expect(names).to eq([ "Bravo", "Alpha" ])
      end

      it "marks the active sort column with a sort-{dir} class on the link" do
        # Polish-2 (2026-05-06): the directional arrow is rendered via
        # the CSS `::after` pseudo-element on the parent `<th>` (the
        # `:has()` rule swaps the neutral `▲\A▼` stack for a single
        # glyph when the link carries `.sort-asc` / `.sort-desc`). The
        # link text is just the bare label so active and inactive
        # headers line up identically at the pixel level.
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        active_link = html.css("thead a").find { |a| a.text.strip == "created" }
        # Default is created_at desc → class is sort-desc.
        expect(active_link["class"].to_s.split).to include("sort-desc")
        # And the link text carries no inline glyph anymore.
        expect(active_link.text).not_to include("▼")
        expect(active_link.text).not_to include("▲")
      end

      it "applies ?sort=footage_duration_seconds&dir=desc" do
        get projects_path, params: { sort: "footage_duration_seconds", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        # Alpha (2058s of footage) > Bravo (60s) under DESC.
        expect(names).to eq([ "Alpha", "Bravo" ])
      end

      it "applies ?sort=notes_words_total&dir=asc" do
        get projects_path, params: { sort: "notes_words_total", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        # Alpha has 6 words, Bravo has 250 → Alpha first under ASC.
        expect(names).to eq([ "Alpha", "Bravo" ])
      end

      it "applies ?sort=name&dir=asc" do
        get projects_path, params: { sort: "name", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        expect(names).to eq([ "Alpha", "Bravo" ])
      end

      it "ignores unknown sort keys and falls back to created_at" do
        # Falls back to the default sort column (created_at) but honors
        # the caller's `dir=asc` (still in the allowlist). Older project
        # comes first under ASC.
        get projects_path, params: { sort: "drop_table_projects", dir: "asc" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        expect(names).to eq([ "Alpha", "Bravo" ])
      end

      it "uses both defaults (created_at DESC) when neither param is supplied" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        expect(names).to eq([ "Bravo", "Alpha" ])
      end

      it "ignores unknown dir values and falls back to desc" do
        get projects_path, params: { sort: "name", dir: "sideways" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        # name desc → Bravo before Alpha.
        expect(names).to eq([ "Bravo", "Alpha" ])
      end

      it "toggles direction when the same column is clicked twice" do
        # First click from default state — sort=name links should request asc.
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        name_link = html.css("thead a").find { |a| a.text.strip.start_with?("name") }
        expect(name_link["href"]).to include("dir=asc")

        # After the asc click, the page renders with sort=name dir=asc.
        # The link should now offer the opposite direction.
        get projects_path, params: { sort: "name", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        name_link = html.css("thead a").find { |a| a.text.strip.start_with?("name") }
        expect(name_link["href"]).to include("dir=desc")
      end
    end

    # Polish-3 (2026-05-06) — Turbo Frame wrapper around the projects
    # index table. Sort-header clicks target the frame so only the
    # table re-renders. Combined with `data-turbo-action=advance`, the
    # URL still updates and back/forward navigation works. The frame
    # element must exist on every render (including the empty state)
    # or Turbo aborts the swap and falls back to full navigation.
    describe "turbo-frame wrapper" do
      it "wraps the empty state in <turbo-frame id='projects-index-table'>" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        frame = html.css("turbo-frame#projects-index-table").first
        expect(frame).not_to be_nil
      end

      context "with projects" do
        let!(:project) { create(:project, name: "Alpha") }

        it "wraps the table inside <turbo-frame id='projects-index-table'>" do
          get projects_path
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#projects-index-table").first
          expect(frame).not_to be_nil
          expect(frame.css("table")).not_to be_empty
          expect(project.persisted?).to be true
        end

        it "stamps data-turbo-frame=projects-index-table on every sort link" do
          get projects_path
          html = Nokogiri::HTML.fragment(response.body)
          sort_links = html.css("turbo-frame#projects-index-table thead a")
          expect(sort_links).not_to be_empty
          sort_links.each do |a|
            expect(a["data-turbo-frame"]).to eq("projects-index-table"),
              "expected data-turbo-frame on sort link #{a.text.strip.inspect}"
            expect(a["data-turbo-action"]).to eq("advance"),
              "expected data-turbo-action=advance on sort link #{a.text.strip.inspect}"
          end
        end
      end
    end

    describe "bulk-select picker markup" do
      it "wires the bulk-select Stimulus controller with project delete type" do
        get projects_path
        expect(response.body).to include('data-controller="bulk-select"')
        expect(response.body).to include('data-bulk-select-entity-name-value="projects"')
        expect(response.body).to include('data-bulk-select-delete-type-value="project"')
      end

      it "omits the panes-related data values (no multi-pane open on /projects)" do
        get projects_path
        expect(response.body).not_to include("data-bulk-select-max-panes-value")
        expect(response.body).not_to include("data-bulk-select-panes-path-value")
      end

      context "with projects" do
        let!(:project_a) { create(:project, name: "Alpha") }
        let!(:project_b) { create(:project, name: "Bravo") }

        it "omits the openHint and openAction targets (panes-specific, controller guards them)" do
          get projects_path
          expect(response.body).not_to include('data-bulk-select-target="openHint"')
          expect(response.body).not_to include('data-bulk-select-target="openAction"')
        end

        it "omits the permanently-hidden wrapper used as a workaround in the previous markup" do
          get projects_path
          expect(response.body).not_to include('hidden style="display: none;"')
        end
      end

      # Always-on bulk shape (2026-05-10) — `/projects` matches `/channels`
      # and `/videos`: checkboxes render from page load, no `[bulk]` toggle
      # in the breadcrumb, no `[cancel]` action, no `bulkCol` target wiring.
      it "does not render a [bulk] toggle link in the breadcrumb" do
        get projects_path
        expect(response.body).not_to include('data-bulk-select-target="bulkToggle"')
        expect(response.body).not_to include("click-&gt;bulk-select#enterBulk")
        html = Nokogiri::HTML.fragment(response.body)
        breadcrumb = html.css(".dot-list").first
        expect(breadcrumb).not_to be_nil, "expected the breadcrumb dot-list at the top of /projects"
        expect(breadcrumb.css('[class="bl"]').map { |n| n.text.strip }).not_to include("bulk")
      end

      context "with projects" do
        let!(:project_a) { create(:project, name: "Alpha") }
        let!(:project_b) { create(:project, name: "Bravo") }

        it "renders the bulk-mode action toolbar always-visible (actions self-hide until count > 0)" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="actions"')
          expect(response.body).to include('data-bulk-select-target="count"')
          expect(response.body).to include('data-bulk-select-target="deleteAction"')
          # The actions container itself must NOT carry the `hidden`
          # attribute — its inner `.action` spans self-hide via
          # `bulk_select_controller#updateActions` instead.
          html = Nokogiri::HTML.fragment(response.body)
          actions = html.css('[data-bulk-select-target="actions"]').first
          expect(actions["hidden"]).to be_nil,
            "expected the actions container to be always-visible (no `hidden` attr), got: #{actions.to_html}"
          # The deleteAction + count spans START hidden — count = 0 on a
          # fresh page load, so neither shows until the user ticks a row.
          expect(response.body).to match(/data-bulk-select-target="count"\s+hidden/)
          expect(response.body).to match(/data-bulk-select-target="deleteAction"\s+hidden/)
        end

        it "renders the bulk-select header + per-row checkbox cells always-visible" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
          # No `bulkCol` target wiring (channels/videos parity — the toggle
          # mechanism is gone, so the gating target goes with it).
          expect(response.body).not_to include('data-bulk-select-target="bulkCol"')
          # one checkbox per project row
          expect(response.body.scan('data-bulk-select-target="checkbox"').size).to eq(2)
          # Every `col-action` cell — header + per-row — must render WITHOUT
          # the `hidden` attribute that the legacy bulk-mode toggle used.
          html = Nokogiri::HTML.fragment(response.body)
          html.css("td.col-action, th.col-action").each do |cell|
            expect(cell["hidden"]).to be_nil,
              "expected `col-action` cell to render without `hidden` (always-on), got: #{cell.to_html}"
          end
        end

        it "does not wire a cancel link (exitBulk is gone alongside enterBulk)" do
          get projects_path
          expect(response.body).not_to include("click-&gt;bulk-select#exitBulk")
          # No [cancel] BracketedLinkComponent anywhere in the actions toolbar.
          html = Nokogiri::HTML.fragment(response.body)
          actions = html.css('[data-bulk-select-target="actions"]').first
          expect(actions).not_to be_nil
          expect(actions.css('[class="bl"]').map { |n| n.text.strip }).not_to include("cancel")
        end

        # Phase B — leading-separator pattern. Each `.action` span carries
        # its own `.action-sep` dot; the JS controller hides the dot on
        # whichever action is first-visible, so the toolbar never starts
        # with a dangling `· [cancel]`.
        it "renders the bulk-toolbar leading-separator pattern" do
          get projects_path
          expect(response.body).to include("bulk-toolbar")
          # Every action span has an `.action-sep` `&middot;` baked in.
          expect(response.body).to match(/<span class="action-sep" hidden>/)
        end

        it "ships with every leading separator hidden in the static initial render" do
          get projects_path
          # The server-rendered initial state must NOT show a `&middot;`
          # before `[cancel]`. Parse the actions container; assert that
          # every `.action-sep` carries the `hidden` attribute (the JS
          # controller only flips them when the toolbar transitions).
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

        # Frame-escape regression guard (2026-05-10). The projects table
        # sits inside `<turbo-frame id="projects-index-table">` so
        # sortable headers can partial-swap. Without `data-turbo-frame="_top"`
        # cascading on the bulk-toolbar actions container, the
        # controller-injected `[delete N]` link would navigate the click
        # inside that frame — the deletions confirmation page (a full-
        # page surface from `shared/_action_screen.html.erb`) has no
        # matching frame in its response, so Turbo would render
        # "Content missing".
        it "stamps data-turbo-frame=_top on the bulk-toolbar actions container" do
          get projects_path
          html = Nokogiri::HTML.fragment(response.body)
          actions = html.css('[data-bulk-select-target="actions"]').first
          expect(actions).not_to be_nil, "expected the bulk-select actions container"
          expect(actions["data-turbo-frame"]).to eq("_top"),
            "bulk-toolbar must escape the projects-index-table frame so [delete N] navigates full-page"
        end
      end
    end
  end

  describe "POST /projects (default-create)" do
    it "creates a project with the default name and redirects to show" do
      expect {
        post projects_path
      }.to change(Project, :count).by(1)

      project = Project.last
      expect(project.name).to eq("Untitled project")
      expect(response).to redirect_to(project_path(project))
    end

    it "renders the show page successfully after the redirect" do
      post projects_path
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Untitled project")
      expect(response.body).to include("footage")
      expect(response.body).to include("notes")
      # Phase 12 realignment (2026-05-10): timelines pane retired,
      # replaced by videos pane (Project has_many :videos).
      expect(response.body).to include("videos")
    end
  end

  describe "GET /projects/:id" do
    let!(:project) { create(:project) }

    it "renders the three panes" do
      get project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("footage")
      expect(response.body).to include("notes")
      # Phase 12 realignment (2026-05-10): timelines pane retired,
      # replaced by videos pane.
      expect(response.body).to include("videos")
    end

    # Polish-3 (2026-05-06) — both the footage and notes tables on the
    # project show page sit inside Turbo Frames. Sort headers / filter
    # chips / `[clear]` for footage target `footage-table`; sort headers
    # for the notes table target `notes-table`. The frames must coexist
    # so each table can re-render independently without affecting the
    # other (and without re-running the whole show page).
    describe "turbo-frame wrappers (footage + notes)" do
      it "renders <turbo-frame id='footage-table'> on the show page" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        frame = html.css("turbo-frame#footage-table").first
        expect(frame).not_to be_nil
      end

      it "renders <turbo-frame id='notes-table'> on the show page" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        frame = html.css("turbo-frame#notes-table").first
        expect(frame).not_to be_nil
      end

      context "with footage and notes" do
        let!(:footage) { create(:footage, project: project, filename: "clip.mkv") }
        let!(:note) { create(:note, project: project, title: "my note") }

        it "houses the footage table inside <turbo-frame id='footage-table'>" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#footage-table").first
          expect(frame).not_to be_nil
          # The footage table is the one whose thead carries `filename`.
          headers = frame.css("table thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
          expect(headers).to include("filename")
        end

        it "houses the notes table inside <turbo-frame id='notes-table'>" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#notes-table").first
          expect(frame).not_to be_nil
          headers = frame.css("table thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
          expect(headers).to include("title")
        end

        it "stamps data-turbo-frame=footage-table on every footage sort link" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          links = html.css("turbo-frame#footage-table thead a")
          expect(links).not_to be_empty
          links.each do |a|
            expect(a["data-turbo-frame"]).to eq("footage-table")
            expect(a["data-turbo-action"]).to eq("advance")
          end
        end

        it "stamps data-turbo-frame=notes-table on every notes sort link" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          links = html.css("turbo-frame#notes-table thead a")
          expect(links).not_to be_empty
          links.each do |a|
            expect(a["data-turbo-frame"]).to eq("notes-table")
            expect(a["data-turbo-action"]).to eq("advance")
          end
        end
      end

      context "with footage variation that triggers filter chips" do
        let!(:obs_clip)    { create(:footage, project: project, filename: "obs.mkv", source: :obs) }
        let!(:camera_clip) { create(:footage, project: project, filename: "cam.mkv", source: :camera) }

        it "stamps data-turbo-frame=footage-table on every footage filter chip" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          chips = html.css("turbo-frame#footage-table a.filter-chip")
          expect(chips).not_to be_empty
          chips.each do |a|
            expect(a["data-turbo-frame"]).to eq("footage-table"),
              "expected data-turbo-frame on chip #{a.text.strip.inspect}"
            expect(a["data-turbo-action"]).to eq("advance"),
              "expected data-turbo-action=advance on chip #{a.text.strip.inspect}"
          end
          expect([ obs_clip, camera_clip ].all?(&:persisted?)).to be true
        end

        it "stamps data-turbo-frame=footage-table on the [clear] link when a filter is active" do
          get project_path(project), params: { source: "obs" }
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#footage-table").first
          expect(frame).not_to be_nil
          clear_link = frame.css("a.bracketed").find { |a| a.css("span.bl").any? { |s| s.text.strip == "clear" } }
          expect(clear_link).not_to be_nil, "expected a [clear] link inside the footage frame"
          expect(clear_link["data-turbo-frame"]).to eq("footage-table")
          expect(clear_link["data-turbo-action"]).to eq("advance")
        end
      end
    end

    # 2026-05-05 UX fix — the footage pane's CLI import snippet
    # (`pito footage import --project N --path <dir>` plus a `[copy]`
    # bracketed link wired to the `clipboard-copy` Stimulus controller)
    # used to render only in the empty-state branch. It now renders
    # ALWAYS — both when the project has footage and when it doesn't —
    # and sits outside the `<turbo-frame id='footage-table'>` so sort/
    # filter swaps don't churn it. The expected literal command string
    # interpolates the project's id verbatim and the `<dir>` placeholder
    # is HTML-escaped because the source code emits it via `&lt;dir&gt;`.
    describe "footage pane — CLI import snippet always visible" do
      let(:expected_command) { "pito footage import --project #{project.id} --path &lt;dir&gt;" }

      shared_examples "renders the CLI import snippet" do
        it "renders the snippet's clipboard-copy controller block" do
          html = Nokogiri::HTML.fragment(response.body)
          block = html.css("div.code-block[data-controller='clipboard-copy']").first
          expect(block).not_to be_nil, "expected a .code-block[data-controller=clipboard-copy] in the footage pane"
        end

        it "renders the literal `pito footage import` command in the snippet" do
          # The HTML-escaped `&lt;dir&gt;` is what ERB emits; raw response
          # body still carries the entity form.
          expect(response.body).to include(expected_command)
        end

        it "renders the [copy] BracketedLink wired to clipboard-copy#copy" do
          html = Nokogiri::HTML.fragment(response.body)
          block = html.css("div.code-block[data-controller='clipboard-copy']").first
          expect(block).not_to be_nil
          copy_link = block.css("a.bracketed").find { |a| a.css("span.bl").any? { |s| s.text.strip == "copy" } }
          expect(copy_link).not_to be_nil, "expected a [copy] bracketed link inside the snippet block"
          expect(copy_link["data-action"]).to eq("click->clipboard-copy#copy")
        end

        it "places the snippet OUTSIDE the <turbo-frame id='footage-table'>" do
          # The snippet has to live above the frame so sort-header /
          # filter-chip swaps don't flicker it. Asserts the snippet
          # block is not a descendant of the footage-table frame.
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#footage-table").first
          expect(frame).not_to be_nil
          inside_frame = frame.css("div.code-block[data-controller='clipboard-copy']")
          expect(inside_frame).to be_empty, "the import snippet must sit outside <turbo-frame id='footage-table'>"
        end
      end

      context "when the project has no footage (empty-state branch)" do
        before { get project_path(project) }
        include_examples "renders the CLI import snippet"

        it "still renders the empty-state 'no footage yet' copy inside the frame" do
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#footage-table").first
          expect(frame).not_to be_nil
          expect(frame.text).to include("no footage yet")
        end
      end

      context "when the project has footage (populated branch)" do
        before do
          create(:footage, project: project, filename: "clip-a.mkv")
          create(:footage, project: project, filename: "clip-b.mkv")
          get project_path(project)
        end

        include_examples "renders the CLI import snippet"

        it "renders the footage table alongside the snippet" do
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#footage-table").first
          expect(frame).not_to be_nil
          headers = frame.css("table.footage-table thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
          expect(headers).to include("filename")
        end
      end
    end

    # Phase B revamp (2026-05-06) — show page is a `.pane-row` of three
    # panes that wrap to a new row when the viewport runs out. The first
    # two panes are 640px (zebra A/B); the third is `.pane--wide` (1280px,
    # always wide tone). No inline pane-bg tokens — the global `.pane` /
    # `.pane--wide` rules handle backgrounds.
    it "renders a .pane-row with three panes (videos, notes, footage--wide)" do
      get project_path(project)
      body = response.body
      expect(body.scan(/class="pane-row"/).size).to eq(1)
      # Phase 12 realignment (2026-05-10): the timelines pane was
      # replaced by the videos pane (Project has_many :videos via the
      # direct nullable Video.project_id column). The previously-
      # separate "linked videos" block below the row was folded into
      # the in-row videos pane, so the layout is back to exactly 3
      # panes: 2 plain + 1 wide.
      plain_panes = body.scan(/class="pane"/).size
      wide_panes  = body.scan(/class="pane pane--wide"/).size
      expect(plain_panes).to eq(2)
      expect(wide_panes).to eq(1)
    end

    # Phase B revamp (2026-05-06) — no inline pane-bg styling. The CSS
    # `.pane:nth-child(even)` and `.pane--wide` rules paint backgrounds.
    it "does not paint cells with inline pane-bg tokens" do
      get project_path(project)
      body = response.body
      expect(body).not_to include("var(--color-pane-bg-a)")
      expect(body).not_to include("var(--color-pane-bg-b)")
      expect(body).not_to include("var(--color-pane-bg-wide)")
    end

    it "renders [e] and [-] in the breadcrumb actions" do
      get project_path(project)
      expect(response.body).to include('class="bl">e</span>')
      expect(response.body).to include('class="bl">-</span>')
      expect(response.body).to include(edit_project_path(project))
    end

    describe "footage table — filename links to edit page (no separate [e] column)" do
      let!(:footage) { create(:footage, project: project, filename: "clip.mkv") }

      it "wraps the filename cell content in an <a> to edit_footage_path" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }
        expect(cell).not_to be_nil
        link = cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(edit_footage_path(footage))
        expect(link.text.strip).to eq("clip.mkv")
      end

      # Turbo Frames bugfix (2026-05-06) — filename link sits inside
      # `<turbo-frame id='footage-table'>` but the edit page has no
      # matching frame. Stamp `data-turbo-frame=_top` so the click
      # escapes the frame and does a full-page navigation.
      it "stamps data-turbo-frame=_top on the filename link (escape the frame on row click)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }
        link = cell.css("a").first
        expect(link["data-turbo-frame"]).to eq("_top")
      end

      it "does NOT stamp data-turbo-frame=_top on footage sort header links (they stay frame-scoped)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        sort_links = html.css("turbo-frame#footage-table thead a")
        expect(sort_links).not_to be_empty
        sort_links.each do |a|
          expect(a["data-turbo-frame"]).not_to eq("_top"),
            "footage sort link #{a.text.strip.inspect} must stay frame-scoped, not escape to _top"
          expect(a["data-turbo-frame"]).to eq("footage-table")
        end
      end

      it "does not render a separate [e] BracketedLinkComponent column for footage" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        # Wave 2 (2026-05-05) — expanded footage table. The `kind` column
        # is gone; `game / fps / bit / duration / size / source` are new.
        # Each header is a sort link, so the visible text is `<label>` (no
        # arrow when not the active sort column). Headers `bit` and `size`
        # were shortened from `bit depth` / `filesize` in a 2026-05-06
        # polish; the underlying sort keys (`bit_depth`, `filesize_bytes`)
        # are unchanged.
        # Phase 7.5 §06 (2026-05-07) — a leading thumb column was added
        # for the median-frame thumbnail; it has no header text and is
        # NOT sortable. Filter it out before comparing against the
        # sortable header list.
        footage_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("filename") }
        expect(footage_table).not_to be_nil
        headers = footage_table.css("thead th").map { |th| th.text.strip }.reject(&:empty?)
        expect(headers).to eq([
          "filename", "game", "resolution", "fps",
          "bit", "duration", "size", "source"
        ])
      end
    end

    describe "notes table — title links to note show page (no separate [e] column)" do
      let!(:note) { create(:note, project: project, title: "my note") }

      it "wraps the title cell in an <a> to note_path" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        link = notes_table.css("tbody tr").first.css("a").find { |a| a["href"] == note_path(note) }
        expect(link).not_to be_nil
        expect(link.text.strip).to eq("my note")
      end

      # Turbo Frames bugfix (2026-05-06) — note title link sits inside
      # `<turbo-frame id='notes-table'>` but the note show page has no
      # matching frame. Stamp `data-turbo-frame=_top` so the click
      # escapes the frame and does a full-page navigation.
      it "stamps data-turbo-frame=_top on the note title link (escape the frame on row click)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        link = notes_table.css("tbody tr").first.css("a").find { |a| a["href"] == note_path(note) }
        expect(link["data-turbo-frame"]).to eq("_top")
      end

      it "does NOT stamp data-turbo-frame=_top on notes sort header links (they stay frame-scoped)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        sort_links = html.css("turbo-frame#notes-table thead a")
        expect(sort_links).not_to be_empty
        sort_links.each do |a|
          expect(a["data-turbo-frame"]).not_to eq("_top"),
            "notes sort link #{a.text.strip.inspect} must stay frame-scoped, not escape to _top"
          expect(a["data-turbo-frame"]).to eq("notes-table")
        end
      end

      it "does not render a separate [e] BracketedLinkComponent column for notes" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        # Phase B polish (2026-05-05) — always-on bulk shape. The
        # checkbox column header is empty text-wise (the `[ ]` indicator
        # is rendered via CSS on the wrapping label), followed by the
        # data columns. NO `[e]` action column.
        # 2026-05-06 — `chars` column dropped; `title`, `words`, `last
        # modified` remain. The active sortable header carries a `↑`/`↓`
        # indicator suffix; strip it before comparing.
        headers = notes_table.css("thead th").map { |th| th.text.strip.sub(/\s*[↑↓▲▼]\z/, "") }
        expect(headers).to eq([ "", "title", "words", "last modified" ])
      end
    end

    # Wave 3.5 (2026-05-06) — notes pane table revamp.
    # 1. `chars` column dropped (the chars_count DB column is being
    #    removed in the same wave).
    # 2. `last modified` and `words` are right-aligned via the `.num`
    #    class on both header and cell.
    # 3. Title / words / last modified are sortable column headers via
    #    the `notes_sort` / `notes_dir` URL params (namespaced so they
    #    coexist with the footage table's `sort` / `dir`).
    describe "notes pane — column drop + alignment + sort" do
      let!(:note_alpha) do
        create(:note, project: project,
               title: "Alpha note", words_count: 100,
               last_modified_at: 2.days.ago)
      end
      let!(:note_bravo) do
        create(:note, project: project,
               title: "Bravo note", words_count: 50,
               last_modified_at: 1.day.ago)
      end

      def notes_table_for(html)
        html.css("table").find do |t|
          t.css("th").map(&:text).map { |s| s.strip.gsub(/[▲▼]/, "").strip }.include?("title")
        end
      end

      it "drops the chars header cell from the table" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        headers = notes_table_for(html).css("thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
        expect(headers).not_to include("chars")
      end

      it "drops the chars per-row td (column count: select + title + words + last modified = 4 cells)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        first_row = notes_table_for(html).css("tbody tr").first
        expect(first_row.css("td").size).to eq(4)
      end

      it "right-aligns the last modified header via the `.num` class" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        last_mod_th = notes_table_for(html).css("thead th").find { |th| th.text.include?("last modified") }
        expect(last_mod_th).not_to be_nil
        expect(last_mod_th["class"].to_s.split).to include("num")
      end

      it "right-aligns the last modified per-row cell via the `.num` class" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        first_row = notes_table_for(html).css("tbody tr").first
        # last cell in the row is the last-modified cell.
        last_mod_td = first_row.css("td").last
        expect(last_mod_td["class"].to_s.split).to include("num")
      end

      it "right-aligns the words header via the `.num` class" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        words_th = notes_table_for(html).css("thead th").find { |th| th.text.include?("words") }
        expect(words_th).not_to be_nil
        expect(words_th["class"].to_s.split).to include("num")
      end

      it "renders title / words / last modified as sortable header links" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        thead = notes_table_for(html).css("thead")
        link_labels = thead.css("a").map { |a| a.text.strip.gsub(/[▲▼]/, "").strip }
        expect(link_labels).to include("title", "words", "last modified")
      end

      it "title sort link sets ?notes_sort=title&notes_dir=asc from the default state" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        title_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(title_link).not_to be_nil
        expect(title_link["href"]).to include("notes_sort=title")
        expect(title_link["href"]).to include("notes_dir=asc")
      end

      it "words sort link sets ?notes_sort=words&notes_dir=asc from the default state" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        words_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("words") }
        expect(words_link).not_to be_nil
        expect(words_link["href"]).to include("notes_sort=words")
        expect(words_link["href"]).to include("notes_dir=asc")
      end

      it "last modified sort link sets ?notes_sort=last_modified&notes_dir=asc on first click" do
        # Default sort is `last_modified desc` — clicking the same column
        # should toggle to `asc` (the opposite direction).
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        lm_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("last modified") }
        expect(lm_link).not_to be_nil
        expect(lm_link["href"]).to include("notes_sort=last_modified")
        expect(lm_link["href"]).to include("notes_dir=asc")
      end

      it "stamps a `sort-desc` class on the active link under the default `last_modified desc` sort" do
        # Polish-2 (2026-05-06) — directional arrow now via CSS `::after`
        # on the parent `<th>`, driven by the `sort-asc` / `sort-desc`
        # class on the inner `<a>`. Assert on the class, not the rendered
        # text — the link no longer carries an inline ▲ / ▼ glyph.
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        lm_link = notes_table_for(html).css("thead a").find { |a| a.text.strip == "last modified" }
        expect(lm_link["class"].to_s.split).to include("sort-desc")
      end

      # Dual-arrow bug fix (2026-05-06). The CSS `th.sortable::after`
      # pseudo-element renders the neutral up/down stack on every
      # sortable header. Without a hook, the active column rendered
      # both the inline directional arrow AND the CSS neutral indicator
      # at once. The helper now stamps `sort-asc` / `sort-desc` on the
      # active link; CSS `:has()` suppresses the pseudo-element on that
      # column so only one indicator remains. The asserts here lock in
      # the contract.
      it "stamps a `sort-desc` class on the active link (default last_modified desc)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        active_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("last modified") }
        expect(active_link["class"].to_s.split).to include("sort-desc")
      end

      it "stamps a `sort-asc` class on the active link when notes_dir=asc" do
        get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        active_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(active_link["class"].to_s.split).to include("sort-asc")
      end

      it "does not stamp a sort-{asc,desc} class on inactive column links" do
        get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        inactive = notes_table_for(html).css("thead a").reject { |a| a.text.strip.start_with?("title") }
        expect(inactive).not_to be_empty
        inactive.each do |a|
          klass = a["class"].to_s.split
          expect(klass).not_to include("sort-asc")
          expect(klass).not_to include("sort-desc")
        end
      end

      # Wave 3.5+ polish (2026-05-06) — the words column renders via
      # `NoteHelper.human_words`, mirroring the `/projects` index notes
      # column shape. Reads as `6w` / `6,225w` rather than the raw int.
      it "renders the words cell as `Nw` via NoteHelper.human_words" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        # Find the row whose first link is the Alpha note (words_count: 100).
        alpha_row = notes_table_for(html).css("tbody tr").find { |tr| tr.css("a").any? { |a| a.text.strip == "Alpha note" } }
        expect(alpha_row).not_to be_nil
        # Words is the third <td> (checkbox / title / words / last modified).
        words_td = alpha_row.css("td")[2]
        expect(words_td.text.strip).to eq("100w")
      end

      it "renders large word counts with comma delimiters and the `w` suffix" do
        big_note = create(:note, project: project,
                          title: "Big note", words_count: 6225,
                          last_modified_at: Time.current)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        big_row = notes_table_for(html).css("tbody tr").find { |tr| tr.css("a").any? { |a| a.text.strip == "Big note" } }
        expect(big_row).not_to be_nil
        words_td = big_row.css("td")[2]
        expect(words_td.text.strip).to eq("6,225w")
        expect(big_note.persisted?).to be true
      end

      it "applies ?notes_sort=title&notes_dir=asc (Alpha before Bravo)" do
        get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        # Pull only note titles (other links — e.g. footage filenames — share the table region).
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Alpha note", "Bravo note" ])
      end

      it "applies ?notes_sort=title&notes_dir=desc (Bravo before Alpha)" do
        get project_path(project), params: { notes_sort: "title", notes_dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Bravo note", "Alpha note" ])
      end

      it "applies ?notes_sort=words&notes_dir=asc (Bravo 50 before Alpha 100)" do
        get project_path(project), params: { notes_sort: "words", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Bravo note", "Alpha note" ])
      end

      it "applies ?notes_sort=words&notes_dir=desc (Alpha 100 before Bravo 50)" do
        get project_path(project), params: { notes_sort: "words", notes_dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Alpha note", "Bravo note" ])
      end

      it "defaults to `last_modified desc` (most recent first — Bravo, then Alpha)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Bravo note", "Alpha note" ])
      end

      it "applies ?notes_sort=last_modified&notes_dir=asc (oldest first — Alpha, then Bravo)" do
        get project_path(project), params: { notes_sort: "last_modified", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        expect(titles).to eq([ "Alpha note", "Bravo note" ])
      end

      it "ignores unknown notes_sort keys and falls back to the default" do
        get project_path(project), params: { notes_sort: "drop_table_notes" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        # Falls back to last_modified desc default → Bravo first.
        expect(titles).to eq([ "Bravo note", "Alpha note" ])
      end

      it "ignores unknown notes_dir values and falls back to desc" do
        get project_path(project), params: { notes_sort: "title", notes_dir: "sideways" }
        html = Nokogiri::HTML.fragment(response.body)
        titles = notes_table_for(html).css("tbody tr a").map { |a| a.text.strip }
        # title desc → Bravo before Alpha.
        expect(titles).to eq([ "Bravo note", "Alpha note" ])
      end

      it "toggles direction when the same notes column is clicked twice" do
        # First click — default state, link offers asc.
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        title_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(title_link["href"]).to include("notes_dir=asc")

        # After asc click, the link should offer desc.
        get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        title_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(title_link["href"]).to include("notes_dir=desc")
      end

      it "preserves the footage table's sort + dir params on a notes header click" do
        # Both tables sortable on the same page. Clicking a notes header
        # while the footage table has an active sort must keep the
        # footage URL state in the resulting link.
        get project_path(project), params: { sort: "duration_seconds", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        title_link = notes_table_for(html).css("thead a").find { |a| a.text.strip.start_with?("title") }
        expect(title_link).not_to be_nil
        expect(title_link["href"]).to include("sort=duration_seconds")
        expect(title_link["href"]).to include("dir=desc")
        expect(title_link["href"]).to include("notes_sort=title")
        expect(title_link["href"]).to include("notes_dir=asc")
      end

      it "preserves the notes table's sort + dir params on a footage header click" do
        # Mirror of the previous case from the footage table's
        # perspective. Click on a footage header should preserve the
        # active notes_sort / notes_dir. Needs at least one footage row
        # to be present — the footage table only renders when the
        # project has footage.
        create(:footage, project: project, filename: "clip.mkv")
        get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        # Footage thead is the table whose headers include "filename".
        footage_table = html.css("table").find { |t| t.css("th").map(&:text).map { |s| s.strip.gsub(/[▲▼]/, "").strip }.include?("filename") }
        expect(footage_table).not_to be_nil
        filename_link = footage_table.css("thead a").find { |a| a.text.strip.start_with?("filename") }
        expect(filename_link).not_to be_nil
        expect(filename_link["href"]).to include("notes_sort=title")
        expect(filename_link["href"]).to include("notes_dir=asc")
      end
    end

    # Phase B polish (2026-05-05) — notes pane bulk shape mirrors what
    # Lane G shipped for /channels and /videos: `[bulk]` toggle dropped,
    # checkboxes always rendered, header carries a select-all checkbox.
    describe "notes pane — always-on bulk shape" do
      let!(:note) { create(:note, project: project, title: "my note") }

      it "drops the [bulk] toggle from the notes-pane heading" do
        get project_path(project)
        # The heading row reads `notes (N) · [+] · [scan]` — no `[bulk]`
        # link, no `bulkToggle` Stimulus target, no `enterBulk` action.
        html = Nokogiri::HTML.fragment(response.body)
        notes_section = html.css("h2").find { |h| h.text.start_with?("notes (") }&.parent
        expect(notes_section).not_to be_nil, "expected an <h2>notes (N)</h2> heading on the show page"
        expect(notes_section.to_html).not_to match(/\[\s*<span class="bl">bulk<\/span>\s*\]/)
        expect(notes_section.to_html).not_to include('data-bulk-select-target="bulkToggle"')
        expect(notes_section.to_html).not_to include("bulk-select#enterBulk")
      end

      it "does not render a [cancel] / 'select items to act on' affordance in the notes pane" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_section = html.css("h2").find { |h| h.text.start_with?("notes (") }&.parent.parent
        expect(notes_section).not_to be_nil
        expect(notes_section.to_html).not_to include("bulk-select#exitBulk")
        expect(notes_section.to_html).not_to include("select items to act on")
      end

      it "renders the per-row checkboxes always (no `hidden` on bulkCol)" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        # Row checkboxes carry `data-bulk-select-target="checkbox"` and
        # live in `<td class="col-action">` cells WITHOUT a `hidden`
        # attribute (always-on shape).
        row_checkbox_cells = notes_table.css("tbody td.col-action")
        expect(row_checkbox_cells).not_to be_empty
        row_checkbox_cells.each do |td|
          expect(td["hidden"]).to be_nil,
            "expected each row's checkbox cell to render without `hidden` (always-on), got: #{td.to_html}"
          expect(td.to_html).to include('data-bulk-select-target="checkbox"')
        end
      end

      it "renders the select-all header checkbox" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        header_cell = notes_table.css("thead th.col-action").first
        expect(header_cell).not_to be_nil, "expected a header `col-action` cell hosting the select-all checkbox"
        expect(header_cell["hidden"]).to be_nil
        expect(header_cell.to_html).to include('data-bulk-select-target="headerCheckbox"')
        expect(header_cell.to_html).to include("change-&gt;bulk-select#toggleAll")
      end

      it "still wires the bulk-select controller with the note delete type" do
        get project_path(project)
        # Backend support: /deletions/note/:ids already routes via Confirmable.
        expect(response.body).to include('data-bulk-select-entity-name-value="notes"')
        expect(response.body).to include('data-bulk-select-delete-type-value="note"')
      end

      it "renders the bulk-toolbar with deleteAction hidden by default" do
        get project_path(project)
        # The `[delete N]` action target is in the DOM but starts hidden;
        # the controller's `updateActions` flips it visible when ≥1 box
        # is checked.
        expect(response.body).to include('data-bulk-select-target="actions"')
        expect(response.body).to match(/data-bulk-select-target="deleteAction"\s+hidden/)
        expect(response.body).to match(/data-bulk-select-target="count"\s+hidden/)
      end

      # Frame-escape regression guard (2026-05-10). The notes table sits
      # inside `<turbo-frame id="notes-table">` so sortable headers can
      # partial-swap. Without `data-turbo-frame="_top"` cascading on the
      # bulk-toolbar actions container, the controller-injected
      # `[delete N]` link would navigate the click inside that frame —
      # the deletions confirmation page (a full-page surface from
      # `shared/_action_screen.html.erb`) has no matching frame in its
      # response, so Turbo would render "Content missing".
      it "stamps data-turbo-frame=_top on the notes-pane bulk-toolbar actions container" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css("turbo-frame#notes-table").css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the notes-pane bulk-select actions container"
        expect(actions["data-turbo-frame"]).to eq("_top"),
          "notes-pane bulk-toolbar must escape the notes-table frame so [delete N] navigates full-page"
      end
    end

    # Regression — `content_for(:title, value)` HTML-escapes string values
    # into a SafeBuffer; the layout previously interpolated that buffer
    # into a plain `"#{...} ~ pito"` string, which dropped the safe-buffer
    # contract and let `<%= %>` re-escape the contents. A project named
    # `Ghost 'n Goblins Resurrection` rendered as
    # `Ghost &amp;#39;n Goblins Resurrection ~ pito` — the browser tab
    # showed the literal text `Ghost &#39;n Goblins Resurrection`.
    # The fix uses `safe_join` to keep the SafeBuffer intact end-to-end so
    # the apostrophe survives as a single `&#39;` entity (which the
    # browser then renders as a literal apostrophe in the tab).
    it "renders apostrophes in the <title> tag without double-escaping" do
      project.update!(name: "Ghost 'n Goblins Resurrection")
      get project_path(project)
      title_match = response.body.match(%r{<title>([^<]*)</title>})
      expect(title_match).not_to be_nil, "expected a <title> tag in the response body"
      title_text = title_match[1]

      # Single-escaped apostrophe is fine — that's what `<%= %>` writes
      # for a SafeBuffer carrying `&#39;`. Browsers render `&#39;` as `'`.
      expect(title_text).to eq("Ghost &#39;n Goblins Resurrection ~ pito")

      # Double-escape (the bug): the `&` from the first escape gets
      # escaped a second time. Must not happen.
      expect(title_text).not_to include("&amp;#39;")
    end

    it "does not render an inline edit form on the show page" do
      get project_path(project)
      # No name input field on show — editing happens on /projects/:id/edit
      expect(response.body).not_to include('name="project[name]"')
    end

    describe "note title middle-truncation in the notes pane" do
      # Mirror of the footage filename pattern (server-side fixed-length
      # middle truncation via `ApplicationHelper#middle_truncate`). Note
      # titles use balanced `head: 10, tail: 10` defaults — note titles
      # don't carry an extension, so an even split reads better than the
      # filename `8 / 12` shape. The cell's `title` attribute carries the
      # full title for hover-reveal; the link text is the compact form.
      let(:long_title)  { "A Very Long Lorem Ipsum Note" }
      let(:short_title) { "Hi" }

      it "truncates long titles to head…tail with a Unicode ellipsis" do
        note = create(:note, project: project, title: long_title)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        link = notes_table.css("tbody tr a").find { |a| a["href"] == note_path(note) }
        expect(link).not_to be_nil
        # head=10, tail=10 → "A Very Lon" + "…" + "Ipsum Note"
        expect(link.text.strip).to eq("A Very Lon…Ipsum Note")
      end

      it "preserves the full title in the cell's title attribute for hover-reveal" do
        note = create(:note, project: project, title: long_title)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        cell = notes_table.css("tbody tr td").find { |td| td["title"] == long_title }
        expect(cell).not_to be_nil, "expected a <td> carrying title=#{long_title.inspect}"
        expect(cell["title"]).to eq(long_title)
      end

      it "renders short titles untouched (length ≤ head + 1 + tail = 21)" do
        note = create(:note, project: project, title: short_title)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        link = notes_table.css("tbody tr a").find { |a| a["href"] == note_path(note) }
        expect(link).not_to be_nil
        expect(link.text.strip).to eq(short_title)
        # No ellipsis on a short title.
        expect(link.text).not_to include("…")
      end

      it "carries the full short title on the cell's title attribute too" do
        note = create(:note, project: project, title: short_title)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        cell = notes_table.css("tbody tr td").find { |td| td["title"] == short_title }
        expect(cell).not_to be_nil
        expect(cell["title"]).to eq(short_title)
        expect(note.persisted?).to be true
      end

      it "renders titles exactly at the threshold (21 chars) untouched" do
        # head + 1 + tail = 21 — the helper returns the input unchanged.
        edge_title = "abcdefghijklmnopqrstu" # 21 chars exactly
        note = create(:note, project: project, title: edge_title)
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        link = notes_table.css("tbody tr a").find { |a| a["href"] == note_path(note) }
        expect(link).not_to be_nil
        expect(link.text.strip).to eq(edge_title)
        expect(link.text).not_to include("…")
      end
    end

    describe "footage filename middle-truncation" do
      # Wave 4.5 swap (2026-05-05) — middle-truncation moved from a CSS-flex
      # two-span pattern to a server-side fixed-length helper
      # (`FootageHelper#filename_truncate_middle`). The cell renders a
      # single text node with a Unicode ellipsis at the seam; the full
      # filename rides along on the cell's `title` attribute.
      let(:long_name) { "Ghost 'n Goblins Resurrection - 2026-04-23 23-34-48.mkv" }
      let(:short_name) { "clip.mkv" }

      it "renders long filenames as a single truncated text node (no head/tail spans)" do
        create(:footage, project: project, filename: long_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == long_name }
        expect(cell).not_to be_nil, "expected a .filename-cell carrying title=#{long_name.inspect}"

        # The two-span flex pattern is gone — no .filename-head /
        # .filename-tail markup should appear.
        expect(cell.css(".filename-head")).to be_empty
        expect(cell.css(".filename-tail")).to be_empty

        # The link text is the compact form: 8 + 1 + 12 = 21 chars,
        # `<head>…<tail>` with a Unicode U+2026 ellipsis.
        link = cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(edit_footage_path(Footage.find_by!(filename: long_name)))
        expect(link.text.strip).to eq("Ghost 'n…23-34-48.mkv")
      end

      it "preserves the full filename in the cell's title attribute for hover-reveal" do
        create(:footage, project: project, filename: long_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == long_name }
        expect(cell).not_to be_nil
        expect(cell["title"]).to eq(long_name)
      end

      it "renders short filenames untouched inside .filename-cell" do
        create(:footage, project: project, filename: short_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == short_name }
        expect(cell).not_to be_nil
        expect(cell.css(".filename-head")).to be_empty
        expect(cell.css(".filename-tail")).to be_empty
        expect(cell.text.strip).to eq(short_name)
        # Ellipsis must NOT appear for a short filename.
        expect(cell.text).not_to include("…")
      end
    end

    # Wave 2 (2026-05-05) — expanded footage table. Conditional filter chips
    # (only render when the project's footage varies on a dimension), URL-
    # state sort, and the new column set.
    describe "footage table expansion" do
      describe "row rendering — new columns" do
        let!(:game) { create(:game, title: "Some Game") }
        let!(:footage) do
          create(:footage,
            project: project,
            filename: "clip.mkv",
            game: game,
            platform: game.platforms.first["platform"],
            resolution: "1920x1080",
            fps: BigDecimal("60.000"),
            bit_depth: 10,
            duration_seconds: 622,
            filesize_bytes: 12_345,
            source: :obs)
        end

        it "renders the game title in the game column" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("Some Game")
        end

        it "renders fps via human_fps (integer-equivalent shows as integer string)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          # 60.000 -> "60" (integer-equivalent collapses to integer string;
          # no trailing `.0` / `.000`).
          expect(tds).to include("60")
          expect(tds).not_to include("60.0")
          expect(tds).not_to include("60.000")
        end

        it "renders bit_depth with a `-bit` suffix" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("10-bit")
        end

        it "renders duration via human_duration (e.g. 622s -> `10m 22s`)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("10m 22s")
        end

        it "renders filesize via human_filesize (e.g. 12345 -> `12.06 KB`)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("12.06 KB")
        end

        it "renders source via human_source (acronym uppercase: `OBS`)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("OBS")
          # The raw enum string is no longer rendered.
          expect(tds).not_to include("obs")
        end

        it "shows em-dash placeholders for nil-valued cells" do
          create(:footage, project: project,
                 filename: "bare.mkv", resolution: nil, fps: nil,
                 duration_seconds: nil, filesize_bytes: nil)
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "bare.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          # filename + game(—) + resolution(—) + fps(—) + bit_depth(`8-bit`)
          # + duration(—) + filesize(—) + source(`OBS`)
          expect(tds.count("—")).to eq(5)
        end
      end

      describe "filter chips — conditional rendering" do
        it "renders no chip groups when the project has no footage" do
          get project_path(project)
          # No `<dim>:` label rows for any dimension; no chip group at all.
          html = Nokogiri::HTML.fragment(response.body)
          chips = html.css("a.filter-chip")
          expect(chips).to be_empty
        end

        it "suppresses chip groups for dimensions with a single distinct value" do
          # Three rows, all 1920x1080, 60fps, 8-bit, obs — no variation
          # anywhere. Spec: "render chips ONLY if there's > 1 distinct
          # value." Expect zero chip rows.
          3.times do
            create(:footage, project: project,
                   resolution: "1920x1080", fps: BigDecimal("60.000"),
                   bit_depth: 8, source: :obs)
          end
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          expect(html.css("a.filter-chip")).to be_empty
        end

        it "renders chips for dimensions that vary" do
          create(:footage, project: project,
                 resolution: "1920x1080", source: :obs)
          create(:footage, project: project,
                 resolution: "3840x2160", source: :camera)
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          # resolution and source both vary; fps / bit_depth / game don't.
          chip_labels = html.css("a.filter-chip .md-check-static-label").map { |n| n.text.strip }
          # Source chip labels mirror the table column's `human_source`
          # output: acronyms uppercase (`OBS`), proper-noun-style for
          # camera (`Camera`). The URL value stays the raw enum string.
          expect(chip_labels).to include("1920x1080", "3840x2160", "OBS", "Camera")
        end

        it "renders the [clear] link only when a filter is active" do
          create(:footage, project: project, source: :obs)
          create(:footage, project: project, source: :camera)

          # No filter — no clear link.
          get project_path(project)
          expect(response.body).not_to match(%r{/projects/#{project.id}\?\W*"\s*class="bracketed"[^>]*>\[<span class="bl">clear</span>\]})

          # Filter active — clear link present, href = project_path (drops
          # all query params, mirrors /channels).
          get project_path(project), params: { source: "obs" }
          expect(response.body).to include('class="bl">clear</span>')
        end
      end

      describe "filter application" do
        let!(:obs_footage)    { create(:footage, project: project, filename: "obs-clip.mkv", source: :obs) }
        let!(:camera_footage) { create(:footage, project: project, filename: "cam-clip.mkv", source: :camera) }

        it "narrows the table to rows matching the source filter" do
          get project_path(project), params: { source: "obs" }
          html = Nokogiri::HTML.fragment(response.body)
          filenames = html.css("td.filename-cell").map { |td| td["title"] }
          expect(filenames).to include("obs-clip.mkv")
          expect(filenames).not_to include("cam-clip.mkv")
        end

        it "ignores unknown source values (no filter applied)" do
          get project_path(project), params: { source: "zzz" }
          html = Nokogiri::HTML.fragment(response.body)
          filenames = html.css("td.filename-cell").map { |td| td["title"] }
          expect(filenames).to include("obs-clip.mkv", "cam-clip.mkv")
        end

        it "narrows by fps (decimal coerced)" do
          obs_footage.update!(fps: BigDecimal("60.000"))
          camera_footage.update!(fps: BigDecimal("30.000"))
          get project_path(project), params: { fps: "60.0" }
          html = Nokogiri::HTML.fragment(response.body)
          filenames = html.css("td.filename-cell").map { |td| td["title"] }
          expect(filenames).to eq([ "obs-clip.mkv" ])
        end
      end

      describe "URL-state sort" do
        let!(:short)  { create(:footage, project: project, filename: "short.mkv", duration_seconds: 30) }
        let!(:medium) { create(:footage, project: project, filename: "medium.mkv", duration_seconds: 600) }
        let!(:long)   { create(:footage, project: project, filename: "long.mkv", duration_seconds: 3600) }

        it "sorts by the requested column + direction" do
          get project_path(project), params: { sort: "duration_seconds", dir: "desc" }
          html = Nokogiri::HTML.fragment(response.body)
          filenames = html.css("td.filename-cell").map { |td| td["title"] }
          expect(filenames).to eq([ "long.mkv", "medium.mkv", "short.mkv" ])
        end

        # Polish-2 (2026-05-06) — directional arrow now via CSS `::after`
        # on the parent `<th>`, driven by the `sort-asc` / `sort-desc`
        # class on the inner `<a>`. Assert on the class, not the text.
        it "stamps a `sort-asc` class on the active link when dir=asc" do
          get project_path(project), params: { sort: "duration_seconds", dir: "asc" }
          html = Nokogiri::HTML.fragment(response.body)
          duration_link = html.css("thead a").find { |a| a.text.strip == "duration" }
          expect(duration_link["class"].to_s.split).to include("sort-asc")
        end

        it "stamps a `sort-desc` class on the active link when dir=desc" do
          get project_path(project), params: { sort: "duration_seconds", dir: "desc" }
          html = Nokogiri::HTML.fragment(response.body)
          duration_link = html.css("thead a").find { |a| a.text.strip == "duration" }
          expect(duration_link["class"].to_s.split).to include("sort-desc")
        end

        it "ignores unknown sort columns and falls back to the default" do
          get project_path(project), params: { sort: "rm -rf /" }
          expect(response).to have_http_status(:ok)
        end

        it "header link toggles the direction on subsequent click (asc -> desc)" do
          get project_path(project), params: { sort: "duration_seconds", dir: "asc" }
          html = Nokogiri::HTML.fragment(response.body)
          duration_th = html.css("thead th").find { |th| th.text.include?("duration") }
          link = duration_th.css("a").first
          expect(link["href"]).to include("sort=duration_seconds")
          expect(link["href"]).to include("dir=desc")
        end

        # Bug fix (2026-05-06): the footage `<th>` cells previously
        # rendered `link_to` content but lacked `class="sortable"`, so
        # the shared CSS treatment (cursor: pointer, neutral ▲▼ glyph,
        # hover background) didn't apply — the headers read as plain
        # text in the user's screenshot. Mirrors `_notes_pane.html.erb`
        # and `/projects` index, which both carry the class.
        describe "sortable header markup parity with notes / index" do
          # Pull only the footage table — the show page also renders a
          # notes table whose <th>s are sortable too. Identify by
          # filename header presence.
          def footage_table(html)
            html.css("table").find do |t|
              t.css("th").map(&:text).map { |s| s.strip.gsub(/[▲▼]/, "").strip }.include?("filename")
            end
          end

          it "marks every footage <th> with class='sortable'" do
            get project_path(project)
            html = Nokogiri::HTML.fragment(response.body)
            # Phase 7.5 §06 (2026-05-07) — the leading thumb column has
            # no header text and is intentionally NOT sortable. Restrict
            # the parity check to the sortable headers (those that carry
            # an `<a>` sort link).
            ths = footage_table(html).css("thead th").select { |th| th.css("a").any? }
            expect(ths.size).to eq(8)
            ths.each do |th|
              expect(th["class"].to_s.split).to include("sortable"),
                "expected class='sortable' on <th>#{th.text.strip}</th>, got class=#{th['class'].inspect}"
            end
          end

          it "wraps every footage header label in a clickable <a>" do
            get project_path(project)
            html = Nokogiri::HTML.fragment(response.body)
            # Phase 7.5 §06 — exclude the non-sortable thumb column.
            ths = footage_table(html).css("thead th").select { |th| th.css("a").any? }
            expect(ths.size).to eq(8)
            ths.each do |th|
              link = th.css("a").first
              expect(link).not_to be_nil,
                "expected <a> inside <th>#{th.text.strip}</th>, got: #{th.to_html}"
              expect(link["href"]).to include("sort=")
              expect(link["href"]).to include("dir=")
            end
          end

          it "preserves the right-aligned `.num` class on numeric headers (fps, bit, duration, size)" do
            get project_path(project)
            html = Nokogiri::HTML.fragment(response.body)
            ths = footage_table(html).css("thead th")
            num_headers = ths.select { |th| th["class"].to_s.split.include?("num") }
            num_labels = num_headers.map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
            expect(num_labels).to eq([ "fps", "bit", "duration", "size" ])
          end

          it "applies ?sort=fps&dir=asc and reorders the table accordingly" do
            short.update!(fps: BigDecimal("60.000"))
            medium.update!(fps: BigDecimal("30.000"))
            long.update!(fps: BigDecimal("24.000"))
            get project_path(project), params: { sort: "fps", dir: "asc" }
            html = Nokogiri::HTML.fragment(response.body)
            filenames = html.css("td.filename-cell").map { |td| td["title"] }
            # 24 < 30 < 60 — long.mkv (24fps) first under asc.
            expect(filenames).to eq([ "long.mkv", "medium.mkv", "short.mkv" ])
          end

          it "stamps a `sort-asc` class on the active fps link when sort=fps&dir=asc" do
            # Polish-2 (2026-05-06) — directional arrow rendered via CSS
            # `::after` on the parent `<th>`, driven by the `sort-asc` /
            # `sort-desc` class on the inner `<a>`. Assert on the class.
            get project_path(project), params: { sort: "fps", dir: "asc" }
            html = Nokogiri::HTML.fragment(response.body)
            fps_link = footage_table(html).css("thead a").find { |a| a.text.strip == "fps" }
            expect(fps_link).not_to be_nil
            expect(fps_link["class"].to_s.split).to include("sort-asc")
          end

          it "ignores ?sort=drop_table and falls back to the local_path default safely" do
            # `local_path` is the default — alphabetical by import path.
            # The factory's filenames double as their local_path tail, so
            # `long.mkv` < `medium.mkv` < `short.mkv` alphabetically.
            # `local_path` is NOT a header in the table (default-only
            # sort key), so when an unknown sort key falls back to it,
            # NO header link should carry the active sort class.
            get project_path(project), params: { sort: "drop_table_footages" }
            expect(response).to have_http_status(:ok)
            html = Nokogiri::HTML.fragment(response.body)
            footage_link_with_active_class = footage_table(html).css("thead a").find do |a|
              klass = a["class"].to_s.split
              klass.include?("sort-asc") || klass.include?("sort-desc")
            end
            expect(footage_link_with_active_class).to be_nil
          end

          it "sort_link_to URLs preserve unrelated query params (notes_sort / notes_dir)" do
            # Click on a footage header while a notes_sort is active —
            # the resulting href should still carry notes_sort/notes_dir
            # so the user doesn't lose the notes table's URL state on
            # any footage click. Mirrors the notes-pane parity case.
            get project_path(project), params: { notes_sort: "title", notes_dir: "asc" }
            html = Nokogiri::HTML.fragment(response.body)
            duration_link = footage_table(html).css("thead a").find { |a| a.text.strip.start_with?("duration") }
            expect(duration_link).not_to be_nil
            expect(duration_link["href"]).to include("notes_sort=title")
            expect(duration_link["href"]).to include("notes_dir=asc")
          end
        end
      end
    end
  end

  describe "GET /projects/:id/edit" do
    let!(:project) { create(:project, name: "Some project") }

    it "returns 200 and renders a form with the name field" do
      get edit_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="project[name]"')
      expect(response.body).to include("Some project")
      # cancel link points back to show
      expect(response.body).to include(project_path(project))
    end
  end

  describe "PATCH /projects/:id (rename)" do
    let!(:project) { create(:project, name: "Untitled project") }

    it "renames the project" do
      patch project_path(project), params: { project: { name: "My new project" } }
      expect(project.reload.name).to eq("My new project")
      expect(response).to redirect_to(project_path(project))
    end
  end

  describe "DELETE /projects/:id" do
    let!(:project) { create(:project) }

    it "destroys the project" do
      expect {
        delete project_path(project)
      }.to change(Project, :count).by(-1)
      expect(response).to redirect_to(projects_path)
    end
  end
end
