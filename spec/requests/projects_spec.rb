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
        # bulkCol(hidden) + name + created + footages + notes + timelines = 6.
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

      it "renders the four numeric columns (created / footage / notes / timelines)" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        headers = html.css("thead th").map { |th| th.text.strip.gsub(/[▲▼]/, "").strip }
        # bulkCol header (empty), action col header (empty), then the five
        # data columns in order. `footage` is the new singular header.
        expect(headers.last(5)).to eq([ "name", "created", "footage", "notes", "timelines" ])
      end

      it "renders the project's footage duration via human_duration and notes word total" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find { |tr| tr.text.include?("Alpha") }
        expect(row).not_to be_nil
        nums = row.css("td.num").map { |td| td.text.strip }
        # First .num is the relative time string; the trailing three are
        # human_duration(footage_duration_seconds) / human_words(notes_words_total) /
        # timelines_count. 2058s -> "34m 18s"; 6 words -> "6w" (compact
        # label with comma-delimited thousands for larger counts).
        expect(nums.last(3)).to eq([ "34m 18s", "6w", "0" ])
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

      it "marks the active sort column with a direction indicator" do
        get projects_path
        html = Nokogiri::HTML.fragment(response.body)
        active_header = html.css("thead a").find { |a| a.text.strip.start_with?("created") }
        # Default is created_at desc → indicator is the ▼ glyph.
        expect(active_header.text).to include("▼")
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
    # cell uses an inline pane-bg token + 12px padding treatment Settings
    # adopted in the same Wave; the legacy `.pane-wrapper` class is gone
    # from this view.
    #
    # Phase B revamp (2026-05-05) — the three cells now wear the three
    # tones of the pane-bg system:
    # - timelines (row 1 left)  -> --color-pane-bg-a
    # - notes     (row 1 right) -> --color-pane-bg-b
    # - footage   (row 2 full)  -> --color-pane-bg-wide
    it "renders the two-row layout with three pane cells (A | B / wide)" do
      get project_path(project)
      body = response.body
      expect(body.scan(/background:\s*var\(--color-pane-bg-a\)/).size).to eq(1)
      expect(body.scan(/background:\s*var\(--color-pane-bg-b\)/).size).to eq(1)
      expect(body.scan(/background:\s*var\(--color-pane-bg-wide\)/).size).to eq(1)
    end

    # Phase B revamp — vertical gap between row 1 (paired) and row 2
    # (wide) so the color separation reads cleanly. The gap lives on the
    # parent flex container, not as per-row margins.
    it "applies a 12px gap between row 1 and row 2" do
      get project_path(project)
      expect(response.body).to match(/flex-direction:\s*column;\s*gap:\s*12px/)
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
        # is gone; `game / fps / bit / duration / size / source` are new.
        # Each header is a sort link, so the visible text is `<label>` (no
        # arrow when not the active sort column). Headers `bit` and `size`
        # were shortened from `bit depth` / `filesize` in a 2026-05-06
        # polish; the underlying sort keys (`bit_depth`, `filesize_bytes`)
        # are unchanged.
        footage_table = html.css("table").find { |t| t.css("th").map(&:text).map(&:strip).include?("filename") }
        expect(footage_table).not_to be_nil
        headers = footage_table.css("thead th").map { |th| th.text.strip }
        expect(headers).to eq([
          "filename", "game", "resolution", "fps",
          "bit", "duration", "size", "source"
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
        create(:note, project: project, tenant: project.tenant,
               title: "Alpha note", words_count: 100,
               last_modified_at: 2.days.ago)
      end
      let!(:note_bravo) do
        create(:note, project: project, tenant: project.tenant,
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

      it "renders the descending arrow on the default `last_modified desc` sort" do
        get project_path(project)
        html = Nokogiri::HTML.fragment(response.body)
        lm_th = notes_table_for(html).css("thead th").find { |th| th.text.include?("last modified") }
        expect(lm_th.text).to include("▼")
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
        big_note = create(:note, project: project, tenant: project.tenant,
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
        create(:footage, project: project, tenant: project.tenant, filename: "clip.mkv")
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
      let!(:note) { create(:note, project: project, tenant: project.tenant, title: "my note") }

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
      # Wave 4.5 swap (2026-05-05) — middle-truncation moved from a CSS-flex
      # two-span pattern to a server-side fixed-length helper
      # (`FootageHelper#filename_truncate_middle`). The cell renders a
      # single text node with a Unicode ellipsis at the seam; the full
      # filename rides along on the cell's `title` attribute.
      let(:long_name) { "Ghost 'n Goblins Resurrection - 2026-04-23 23-34-48.mkv" }
      let(:short_name) { "clip.mkv" }

      it "renders long filenames as a single truncated text node (no head/tail spans)" do
        create(:footage, project: project, tenant: project.tenant, filename: long_name)
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
        create(:footage, project: project, tenant: project.tenant, filename: long_name)
        get project_path(project)

        html = Nokogiri::HTML.fragment(response.body)
        cell = html.css("td.filename-cell").find { |td| td["title"] == long_name }
        expect(cell).not_to be_nil
        expect(cell["title"]).to eq(long_name)
      end

      it "renders short filenames untouched inside .filename-cell" do
        create(:footage, project: project, tenant: project.tenant, filename: short_name)
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
          create(:footage, project: project, tenant: project.tenant,
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
          # Source chip labels mirror the table column's `human_source`
          # output: acronyms uppercase (`OBS`), proper-noun-style for
          # camera (`Camera`). The URL value stays the raw enum string.
          expect(chip_labels).to include("1920x1080", "3840x2160", "OBS", "Camera")
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
            ths = footage_table(html).css("thead th")
            expect(ths.size).to eq(8)
            ths.each do |th|
              expect(th["class"].to_s.split).to include("sortable"),
                "expected class='sortable' on <th>#{th.text.strip}</th>, got class=#{th['class'].inspect}"
            end
          end

          it "wraps every footage header label in a clickable <a>" do
            get project_path(project)
            html = Nokogiri::HTML.fragment(response.body)
            ths = footage_table(html).css("thead th")
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

          it "renders the ▲ arrow on the active fps header when sort=fps&dir=asc" do
            get project_path(project), params: { sort: "fps", dir: "asc" }
            html = Nokogiri::HTML.fragment(response.body)
            fps_th = footage_table(html).css("thead th").find { |th| th.text.strip.gsub(/[▲▼]/, "").strip == "fps" }
            expect(fps_th).not_to be_nil
            expect(fps_th.text).to include("▲")
          end

          it "ignores ?sort=drop_table and falls back to the local_path default safely" do
            # `local_path` is the default — alphabetical by import path.
            # The factory's filenames double as their local_path tail, so
            # `long.mkv` < `medium.mkv` < `short.mkv` alphabetically.
            get project_path(project), params: { sort: "drop_table_footages" }
            expect(response).to have_http_status(:ok)
            html = Nokogiri::HTML.fragment(response.body)
            footage_th_with_arrow = footage_table(html).css("thead th").find { |th| th.text.match?(/[▲▼]/) }
            # No allowlisted match → no active header (every header
            # renders without an arrow on fallback).
            expect(footage_th_with_arrow).to be_nil
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
