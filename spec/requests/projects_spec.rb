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

    # Phase 4 Wave 2 — `/projects` index revamp. The sortable column headers
    # mirror the URL-state pattern from `ChannelsController` (sort + dir
    # query params, sanitized through an allowlist).
    describe "expanded index columns + sort" do
      let!(:project_a) { create(:project, name: "Alpha", created_at: 2.days.ago) }
      let!(:project_b) { create(:project, name: "Bravo", created_at: 1.day.ago) }

      before do
        # Hand-set the counter caches so the SQL ORDER BY has something to
        # discriminate on without going through the full create-footage path.
        project_a.update_columns(footages_count: 4, notes_count: 1, timelines_count: 0)
        project_b.update_columns(footages_count: 1, notes_count: 5, timelines_count: 2)
      end

      it "renders the four numeric columns (created / footages / notes / timelines)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        headers = html.css("thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
        # bulkCol header (empty), action col header (empty), then the five
        # data columns in order.
        expect(headers.last(5)).to eq([ "name", "created", "footages", "notes", "timelines" ])
      end

      it "renders each project's footages/notes/timelines counter values" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find { |tr| tr.text.include?("Alpha") }
        expect(row).not_to be_nil
        nums = row.css("td.num").map { |td| td.text.strip }
        # First .num is the relative time string; the trailing three are
        # footages / notes / timelines counters.
        expect(nums.last(3)).to eq([ "4", "1", "0" ])
      end

      it "renders the project name as a link to the show page" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("tbody tr a").find { |a| a.text.strip == "Alpha" }
        expect(link).not_to be_nil
        expect(link["href"]).to eq(project_path(project_a))
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

        footages_link = html.css("thead a").find { |a| a.text.strip.start_with?("footages") }
        expect(footages_link).not_to be_nil
        expect(footages_link["href"]).to include("sort=footages_count")
      end

      it "defaults to created_at DESC ordering (most recent first)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        expect(names).to eq([ "Bravo", "Alpha" ])
      end

      it "marks the active sort column with a direction indicator" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        active_header = html.css("thead a").find { |a| a.text.strip.start_with?("created") }
        # Default is created_at desc → indicator is the ▼ glyph.
        expect(active_header.text).to include("▼")
      end

      it "applies ?sort=footages_count&dir=desc" do
        get projects_path, params: { sort: "footages_count", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        # Alpha (4 footages) > Bravo (1 footage) under DESC.
        expect(names).to eq([ "Alpha", "Bravo" ])
      end

      it "applies ?sort=notes_count&dir=asc" do
        get projects_path, params: { sort: "notes_count", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        names = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| %w[Alpha Bravo].include?(t) }
        # Alpha has 1 note, Bravo has 5 → Alpha first under ASC.
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

      it "renders the [ bulk ] toggle link" do
        get projects_path
        expect(response.body).to include('data-bulk-select-target="bulkToggle"')
        expect(response.body).to include("click-&gt;bulk-select#enterBulk")
      end

      context "with projects" do
        let!(:project_a) { create(:project, name: "Alpha") }
        let!(:project_b) { create(:project, name: "Bravo") }

        it "renders the bulk-mode action toolbar (hidden by default)" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="actions"')
          expect(response.body).to include('data-bulk-select-target="count"')
          expect(response.body).to include('data-bulk-select-target="deleteAction"')
        end

        it "renders the bulk-select header + per-row checkbox columns (hidden by default)" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
          expect(response.body).to include('data-bulk-select-target="bulkCol"')
          # one checkbox per project row
          expect(response.body.scan('data-bulk-select-target="checkbox"').size).to eq(2)
        end

        it "wires the cancel link to exitBulk" do
          get projects_path
          expect(response.body).to include("click-&gt;bulk-select#exitBulk")
        end

        # Phase B — leading-separator pattern. Each `.action` span carries
        # its own `.action-sep` dot; the JS controller hides the dot on
        # whichever action is first-visible, so the toolbar never starts
        # with a dangling `· [ cancel ]`.
        it "renders the bulk-toolbar leading-separator pattern" do
          get projects_path
          expect(response.body).to include("bulk-toolbar")
          # Every action span has an `.action-sep` `&middot;` baked in.
          expect(response.body).to match(/<span class="action-sep" hidden>/)
        end

        it "ships with every leading separator hidden in the static initial render" do
          get projects_path
          # The server-rendered initial state must NOT show a `&middot;`
          # before `[ cancel ]`. Parse the actions container; assert that
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
      expect(response.body).to include("timelines")
    end
  end

  describe "GET /projects/:id" do
    let!(:project) { create(:project) }

    it "renders the three panes" do
      get project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("footage")
      expect(response.body).to include("notes")
      expect(response.body).to include("timelines")
    end

    # Wave 2 (2026-05-05) — show page restructured into a 2-row layout
    # (timelines | notes on row 1, footage full-width on row 2). Each
    # cell uses the same inline `var(--color-pane-bg)` + 12px padding
    # treatment Settings adopted in the same Wave; the legacy
    # `.pane-wrapper` class is gone from this view.
    it "renders the two-row layout with three pane cells (inline-styled)" do
      get project_path(project)
      # Row 1 has a 2-column grid; row 2 spans full width. Three cells
      # total carry the pane-bg treatment.
      pane_cells = response.body.scan(/background:\s*var\(--color-pane-bg\)/).size
      expect(pane_cells).to eq(3)
    end

    it "renders [e] and [-] in the breadcrumb actions" do
      get project_path(project)
      expect(response.body).to include('class="bl">e</span>')
      expect(response.body).to include('class="bl">-</span>')
      expect(response.body).to include(edit_project_path(project))
    end

    describe "footage table — filename links to edit page (no separate [e] column)" do
      let!(:footage) { create(:footage, project: project, tenant: project.tenant, filename: "clip.mkv") }

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

      it "does not render a separate [e] BracketedLinkComponent column for footage" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        # Wave 2 (2026-05-05) — expanded footage table. The `kind` column
        # is gone; `game / fps / bit depth / filesize / source` are new.
        # Each header is a sort link, so the visible text is `<label>` (no
        # arrow when not the active sort column).
        footage_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("filename") }
        expect(footage_table).not_to be_nil
        headers = footage_table.css("thead th").map { |th| th.text.strip }
        expect(headers).to eq([
          "filename", "game", "resolution", "fps",
          "bit depth", "duration", "filesize", "source"
        ])
      end
    end

    describe "notes table — title links to note show page (no separate [e] column)" do
      let!(:note) { create(:note, project: project, tenant: project.tenant, title: "my note") }

      it "wraps the title cell in an <a> to note_path" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        link = notes_table.css("tbody tr").first.css("a").find { |a| a["href"] == note_path(note) }
        expect(link).not_to be_nil
        expect(link.text.strip).to eq("my note")
      end

      it "does not render a separate [e] BracketedLinkComponent column for notes" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        notes_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("title") }
        expect(notes_table).not_to be_nil
        # bulk-select checkbox col is hidden by default but still in the DOM;
        # we expect: bulkCol(hidden), title, chars, words, last modified
        # — i.e., NO action column for [e].
        headers = notes_table.css("thead th").map { |th| th.text.strip }
        expect(headers).to eq([ "", "title", "chars", "words", "last modified" ])
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

    describe "footage filename middle-truncation" do
      let(:long_name) { "Ghost 'n Goblins Resurrection - 2026-04-23 23-34-48.mkv" }
      let(:short_name) { "clip.mkv" }

      it "splits long filenames into .filename-head + .filename-tail spans" do
        create(:footage, project: project, tenant: project.tenant, filename: long_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == long_name }
        expect(cell).not_to be_nil, "expected a .filename-cell carrying title=#{long_name.inspect}"

        head = cell.css(".filename-head").first
        tail = cell.css(".filename-tail").first
        expect(head).not_to be_nil
        expect(tail).not_to be_nil
        expect(tail.text).to end_with("23-34-48.mkv")
        expect((head.text + tail.text)).to eq(long_name)
      end

      it "renders short filenames as plain text inside .filename-cell (no head/tail spans)" do
        create(:footage, project: project, tenant: project.tenant, filename: short_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == short_name }
        expect(cell).not_to be_nil
        expect(cell.css(".filename-head")).to be_empty
        expect(cell.css(".filename-tail")).to be_empty
        expect(cell.text.strip).to eq(short_name)
      end
    end

    # Wave 2 (2026-05-05) — expanded footage table. Conditional filter chips
    # (only render when the project's footage varies on a dimension), URL-
    # state sort, and the new column set.
    describe "footage table expansion" do
      describe "row rendering — new columns" do
        let!(:game) { create(:game, tenant: project.tenant, title: "Some Game") }
        let!(:footage) do
          create(:footage,
            project: project,
            tenant: project.tenant,
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

        it "renders fps as a float-style decimal (60.0 not 60.000)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("60.0")
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

        it "renders source as the enum string (`obs`)" do
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "clip.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          expect(tds).to include("obs")
        end

        it "shows em-dash placeholders for nil-valued cells" do
          create(:footage, project: project, tenant: project.tenant,
                 filename: "bare.mkv", resolution: nil, fps: nil,
                 duration_seconds: nil, filesize_bytes: nil)
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          row = html.css("td.filename-cell").find { |td| td["title"] == "bare.mkv" }.parent
          tds = row.css("td").map { |td| td.text.strip }
          # filename + game(—) + resolution(—) + fps(—) + bit_depth(`8-bit`)
          # + duration(—) + filesize(—) + source(`obs`)
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
            create(:footage, project: project, tenant: project.tenant,
                   resolution: "1920x1080", fps: BigDecimal("60.000"),
                   bit_depth: 8, source: :obs)
          end
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          expect(html.css("a.filter-chip")).to be_empty
        end

        it "renders chips for dimensions that vary" do
          create(:footage, project: project, tenant: project.tenant,
                 resolution: "1920x1080", source: :obs)
          create(:footage, project: project, tenant: project.tenant,
                 resolution: "3840x2160", source: :camera)
          get project_path(project)
          html = Nokogiri::HTML.fragment(response.body)
          # resolution and source both vary; fps / bit_depth / game don't.
          chip_labels = html.css("a.filter-chip .md-check-static-label").map { |n| n.text.strip }
          expect(chip_labels).to include("1920x1080", "3840x2160", "obs", "camera")
        end

        it "renders the [clear] link only when a filter is active" do
          create(:footage, project: project, tenant: project.tenant, source: :obs)
          create(:footage, project: project, tenant: project.tenant, source: :camera)

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
        let!(:obs_footage)    { create(:footage, project: project, tenant: project.tenant, filename: "obs-clip.mkv", source: :obs) }
        let!(:camera_footage) { create(:footage, project: project, tenant: project.tenant, filename: "cam-clip.mkv", source: :camera) }

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
        let!(:short)  { create(:footage, project: project, tenant: project.tenant, filename: "short.mkv", duration_seconds: 30) }
        let!(:medium) { create(:footage, project: project, tenant: project.tenant, filename: "medium.mkv", duration_seconds: 600) }
        let!(:long)   { create(:footage, project: project, tenant: project.tenant, filename: "long.mkv", duration_seconds: 3600) }

        it "sorts by the requested column + direction" do
          get project_path(project), params: { sort: "duration_seconds", dir: "desc" }
          html = Nokogiri::HTML.fragment(response.body)
          filenames = html.css("td.filename-cell").map { |td| td["title"] }
          expect(filenames).to eq([ "long.mkv", "medium.mkv", "short.mkv" ])
        end

        it "renders an ascending arrow when the active sort is asc" do
          get project_path(project), params: { sort: "duration_seconds", dir: "asc" }
          html = Nokogiri::HTML.fragment(response.body)
          duration_th = html.css("thead th").find { |th| th.text.include?("duration") }
          expect(duration_th.text).to include("▲")
        end

        it "renders a descending arrow when the active sort is desc" do
          get project_path(project), params: { sort: "duration_seconds", dir: "desc" }
          html = Nokogiri::HTML.fragment(response.body)
          duration_th = html.css("thead th").find { |th| th.text.include?("duration") }
          expect(duration_th.text).to include("▼")
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
