require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:search_engine) do
    instance_double(
      Search::MeilisearchEngine,
      healthy?: true,
      index_stats: {},
      per_index_stats: {}
    )
  end

  before do
    allow(Search).to receive(:engine).and_return(search_engine)
  end

  describe "GET /settings" do
    it "returns 200" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end

    # Phase 24 — Google card was dropped from /settings. The Google
    # management UI moved to /channels (banner on index + per-channel
    # inline panel on show).
    #
    # 2026-05-10 follow-up — the YouTube credentials surface is back
    # as a read-only STATUS card (no input fields). Editing the
    # credentials still happens via `rails credentials:edit` per
    # CLAUDE.md's secrets-only-in-credentials hard rule.

    # 2026-05-11 — YouTube credentials moved out of
    # `Rails.application.credentials.google_oauth` into the AppSetting
    # singleton (Voyage-style edit form). The pane is now an EDIT
    # form, not a read-only status card; assertions target form
    # fields, placeholders, and the "leave blank to keep current"
    # hint mirrored from Voyage.

    it "renders the YouTube credentials edit form with all four fields" do
      AppSetting.delete_all
      get settings_path
      expect(response.body).to include("<h2>YouTube</h2>")
      # Field labels mirror the four-row layout.
      expect(response.body).to include("public API key")
      expect(response.body).to include("OAuth client ID")
      expect(response.body).to include("OAuth client secret")
      expect(response.body).to include("OAuth redirect URI")
      # Four `name=` form inputs — the unambiguous form-input
      # fingerprint.
      expect(response.body).to include('name="settings[youtube_api_key]"')
      expect(response.body).to include('name="settings[youtube_client_id]"')
      expect(response.body).to include('name="settings[youtube_client_secret]"')
      expect(response.body).to include('name="settings[youtube_redirect_uri]"')
      # Section identifier on the wire.
      expect(response.body).to match(/<input type="hidden" name="section" value="youtube">/)
    end

    it "renders the YouTube pane inside a PATCH form, not a read-only list" do
      AppSetting.delete_all
      get settings_path
      youtube_section = response.body[
        /<legend><h2>YouTube<\/h2><\/legend>.*?<\/fieldset>/m
      ]
      expect(youtube_section).not_to be_nil
      # The old read-only `<ul>` list and the credentials-edit hint
      # are gone.
      expect(youtube_section).not_to include("<ul")
      expect(youtube_section).not_to include("Rails.application.credentials.google_oauth")
      expect(youtube_section).not_to include("rails credentials:edit")
    end

    describe "sensitive field placeholders" do
      it "renders 'no key configured' when api_key + client_secret are blank" do
        AppSetting.delete_all
        get settings_path
        expect(response.body).to match(
          /name="settings\[youtube_api_key\]"[^>]*placeholder="no key configured"/
        )
        expect(response.body).to match(
          /name="settings\[youtube_client_secret\]"[^>]*placeholder="no key configured"/
        )
      end

      it "renders 'key configured (•••••••)' when api_key + client_secret are set, and never echoes the plaintext" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_api_key: "AIzaSyFAKEAPIKEYPLAINTEXT_42",
          youtube_client_secret: "GOCSPX-FAKE_CLIENT_SECRET_42"
        )
        get settings_path
        expect(response.body).to include('placeholder="key configured (•••••••)"')
        # The plaintext NEVER lands in the response body.
        expect(response.body).not_to include("AIzaSyFAKEAPIKEYPLAINTEXT_42")
        expect(response.body).not_to include("GOCSPX-FAKE_CLIENT_SECRET_42")
      end

      it "uses type=password for the two sensitive fields" do
        AppSetting.delete_all
        get settings_path
        expect(response.body).to match(
          /<input type="password"[^>]*name="settings\[youtube_api_key\]"/
        )
        expect(response.body).to match(
          /<input type="password"[^>]*name="settings\[youtube_client_secret\]"/
        )
      end
    end

    describe "non-sensitive field placeholders" do
      it "renders the stored client_id verbatim as the placeholder" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_client_id: "987654-abc.apps.googleusercontent.com"
        )
        get settings_path
        expect(response.body).to match(
          /name="settings\[youtube_client_id\]"[^>]*placeholder="987654-abc\.apps\.googleusercontent\.com"/
        )
      end

      it "renders the stored redirect_uri verbatim as the placeholder" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_redirect_uri: "https://custom.example.test/cb"
        )
        get settings_path
        expect(response.body).to match(
          /name="settings\[youtube_redirect_uri\]"[^>]*placeholder="https:\/\/custom\.example\.test\/cb"/
        )
      end

      it "renders the production fallback + '(default)' suffix on the redirect_uri placeholder when blank" do
        AppSetting.delete_all
        get settings_path
        expect(response.body).to match(
          %r{name="settings\[youtube_redirect_uri\]"[^>]*placeholder="https://app\.pitomd\.com/auth/google/callback \(default\)"}
        )
      end
    end

    describe "clear checkboxes (Voyage pattern)" do
      it "renders no clear checkboxes when every field is blank" do
        AppSetting.delete_all
        get settings_path
        expect(response.body).not_to include('name="settings[clear_youtube_api_key]"')
        expect(response.body).not_to include('name="settings[clear_youtube_client_id]"')
        expect(response.body).not_to include('name="settings[clear_youtube_client_secret]"')
        expect(response.body).not_to include('name="settings[clear_youtube_redirect_uri]"')
      end

      it "renders a clear checkbox only for fields that are populated" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_api_key: "k_api",
          youtube_client_id: "k_id"
        )
        get settings_path
        # Two fields are set → two checkboxes.
        expect(response.body).to include('name="settings[clear_youtube_api_key]" value="yes"')
        expect(response.body).to include('name="settings[clear_youtube_client_id]" value="yes"')
        # Two fields are blank → no checkboxes for them.
        expect(response.body).not_to include('name="settings[clear_youtube_client_secret]"')
        expect(response.body).not_to include('name="settings[clear_youtube_redirect_uri]"')
      end

      it "ships yes/no values on the wire (not true/false)" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_api_key: "k_api"
        )
        get settings_path
        expect(response.body).to include('name="settings[clear_youtube_api_key]" value="yes"')
        expect(response.body).not_to include('name="settings[clear_youtube_api_key]" value="true"')
        expect(response.body).not_to include('name="settings[clear_youtube_api_key]" value="false"')
      end
    end

    describe "'leave blank to keep current' hint" do
      it "renders the hint when at least one field is configured" do
        AppSetting.delete_all
        AppSetting.create!(
          key: "max_panes", value: "5",
          youtube_api_key: "k_api"
        )
        get settings_path
        expect(response.body).to include("leave blank to keep current; submit to replace.")
      end

      it "hides the hint when every field is blank" do
        AppSetting.delete_all
        get settings_path
        youtube_section = response.body[
          /<legend><h2>YouTube<\/h2><\/legend>.*?<\/fieldset>/m
        ]
        expect(youtube_section).not_to include("leave blank to keep current")
      end
    end

    it "renders the encrypted-at-rest footer line" do
      AppSetting.delete_all
      get settings_path
      expect(response.body).to include("credentials stored encrypted in the database; never echoed.")
    end

    it "renders the encrypted-at-rest footer line inside the Voyage.ai pane" do
      AppSetting.delete_all
      get settings_path
      voyage_section = response.body[
        /<legend><h2>Voyage\.ai<\/h2><\/legend>.*?<\/fieldset>/m
      ]
      expect(voyage_section).to include("credentials stored encrypted in the database; never echoed.")
    end

    it "does NOT render the Google connection card" do
      get settings_path
      expect(response.body).not_to include("<h2>Google</h2>")
      expect(response.body).not_to include("connected: yes")
      expect(response.body).not_to include("connected: no")
    end

    it "shows the theme selector" do
      get settings_path
      # 2026-05-11 — the section heading was renamed from `appearance`
      # to `ui / ux` when keyboard navigation joined the pane. The
      # internal `section` form value still ships as `appearance` for
      # backward compatibility with scripted PATCH callers.
      expect(response.body).to include("<h2>ui / ux</h2>")
      expect(response.body).not_to include("<h2>appearance</h2>")
      expect(response.body).to include("light")
      expect(response.body).to include("dark")
      expect(response.body).to include("auto (system)")
    end

    # 2026-05-11 — keyboard-navigation master toggle on the ui / ux pane.
    # The row renders a yes/no radio pair (rendered labels: "on" / "off")
    # so the visual matches the theme picker above it. Default state
    # post-migration is "on" — AppSetting.keyboard_navigation_enabled?
    # returns true when no row exists.
    describe "keyboard navigation row" do
      it "renders the row under the ui / ux fieldset" do
        get settings_path
        expect(response.body).to include("keyboard navigation")
        expect(response.body).to include('name="settings[keyboard_navigation_enabled]"')
      end

      it "ships yes/no values on the wire (not true/false)" do
        get settings_path
        expect(response.body).to include('name="settings[keyboard_navigation_enabled]" value="yes"')
        expect(response.body).to include('name="settings[keyboard_navigation_enabled]" value="no"')
        expect(response.body).not_to include('name="settings[keyboard_navigation_enabled]" value="true"')
        expect(response.body).not_to include('name="settings[keyboard_navigation_enabled]" value="false"')
      end

      it "checks the 'yes' radio by default (keyboard nav on)" do
        AppSetting.delete_all
        get settings_path
        expect(response.body).to match(/<input type="radio" name="settings\[keyboard_navigation_enabled\]" value="yes"[^>]*\bchecked\b/)
      end

      it "checks the 'no' radio when the setting is off" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(keyboard_navigation_enabled: false)
        get settings_path
        expect(response.body).to match(/<input type="radio" name="settings\[keyboard_navigation_enabled\]" value="no"[^>]*\bchecked\b/)
      end

      it "labels the radio options as 'on' and 'off'" do
        get settings_path
        # Labels live inside `.md-radio-label` spans.
        expect(response.body).to match(/<span class="md-radio-label">on<\/span>/)
        expect(response.body).to match(/<span class="md-radio-label">off<\/span>/)
      end
    end

    it "shows the Voyage.ai fieldset with the current flag value" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk_test",
        voyage_index_project_notes: true
      )
      get settings_path
      expect(response.body).to include("Voyage.ai")
      expect(response.body).to include("project notes")
      # The "yes" radio for voyage_index_project_notes is checked
      expect(response.body).to match(/<input type="radio" name="settings\[voyage_index_project_notes\]" value="yes"[^>]*\bchecked\b/)
    end

    it "renders four independent forms (workspaces, appearance, voyage, youtube)" do
      # 2026-05-11 — YouTube credentials moved into the AppSetting
      # singleton; the YouTube pane is now an edit form with section
      # identifier `youtube` (NOT `youtube_oauth`, which was the
      # dropped Phase 24 form).
      get settings_path
      # Each per-section form carries a hidden `section` field.
      expect(response.body).to include('value="workspaces"')
      expect(response.body).to include('value="appearance"')
      expect(response.body).to include('value="voyage"')
      expect(response.body).to include('value="youtube"')
      # The dropped Phase 24 section value is still gone.
      expect(response.body).not_to include('value="youtube_oauth"')
    end

    # Phase B polish (2026-05-04) — the per-target Voyage flag radios are
    # only useful once a key is configured (model validation rejects "yes"
    # without one). Hide them when the key is blank.
    it "hides the Voyage per-target flag radios when no key is configured" do
      get settings_path
      expect(AppSetting.voyage_configured?).to be(false)
      expect(response.body).not_to include('name="settings[voyage_index_project_notes]"')
    end

    it "shows the Voyage per-target flag radios once a key is configured" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(voyage_api_key: "vk_test")
      get settings_path
      expect(AppSetting.voyage_configured?).to be(true)
      expect(response.body).to include('name="settings[voyage_index_project_notes]"')
    end

    # Phase B polish — theme is the first form field encountered on the
    # page. Asserting via DOM order: the appearance fieldset's theme radios
    # appear before the workspaces fieldset's pane_title_length input.
    it "renders the theme radios before the pane_title_length input" do
      get settings_path
      theme_position = response.body.index('name="settings[theme]"')
      pane_position = response.body.index("settings_pane_title_length")
      expect(theme_position).not_to be_nil
      expect(pane_position).not_to be_nil
      expect(theme_position).to be < pane_position
    end

    # Phase B polish — reindex is no longer a direct POST button but a
    # bracketed link that opens a ConfirmModalComponent dialog. The form
    # is rendered inside the dialog, not in the fieldset top-level.
    it "renders the reindex action as a modal trigger + ConfirmModalComponent" do
      get settings_path
      expect(response.body).to include('id="reindex_meilisearch_modal"')
      expect(response.body).to include("modal-trigger")
      expect(response.body).to include("reindex Meilisearch?")
    end

    it "uses the .md-radio CSS pattern for the theme radio group" do
      get settings_path
      expect(response.body).to include('class="md-radio"')
      expect(response.body).to include("md-radio-indicator")
      expect(response.body).to include("md-radio-label")
    end

    # Phase B revamp (2026-05-05) — settings page restructured from a 5-pane
    # horizontal strip into a 3-row stacked layout. Rows 1 + 2 hold two 50/50
    # cells; row 3 is full-width. Each cell still wears the pane visual style
    # (`var(--color-pane-bg)` background). Per-section submit buttons read
    # `[update]` (no inner spaces), aligning with the site-wide label revamp.
    it "uses [update] (no inner spaces) on every per-section submit button" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(voyage_api_key: "vk_test")
      get settings_path
      # 2026-05-11 — four per-section forms now: appearance,
      # workspaces, voyage, youtube (YouTube credentials moved into
      # AppSetting as a Voyage-style edit form).
      expect(response.body.scan("[update]").length).to be >= 4
      # The pre-revamp `[save]` text is gone everywhere on the page.
      expect(response.body).not_to include("[save]")
    end

    it "renders settings as six .pane-row groups holding eleven total panes" do
      # 2026-05-10 follow-up — Phase 24 dropped Google + YouTube to
      # four rows / seven panes; restoring the YouTube read-only
      # credentials status card as its own single-pane row pushes the
      # total back to five rows / eight panes.
      # 2026-05-11 — Phase 26 / 01a Timezone foundation lands a ninth
      # pane on row 5 (paired with the previously single `user` pane).
      # 2026-05-11 — Phase 26 / 01b + 01c Slack + Discord webhook
      # panes land as a new paired row, lifting the totals to six
      # rows / eleven panes.
      # 2026-05-11 (later) — stack restructure per user direction:
      # Redis demoted from a standalone pane into a hairline-fenced
      # sub-section of the new `db` pane (which replaced `sql`), and
      # storage goes to a single wide pane (`.pane--wide`) with a
      # 2-column inner layout (assets | notes). Total drops to
      # eleven panes across the same six pane-rows.
      # Layout:
      #   row 1 — ui / ux | workspaces        (2 panes)
      #   row 2 — YouTube | Voyage.ai         (2 panes)
      #   row 3 — user | time zone            (2 panes; Phase 26 01a)
      #   row 4 — OAuth+tokens | sessions     (2 panes; the OAuth /
      #     tokens cell still combines TWO sub-sections separated by
      #     a `<hr class="hairline">`, but counts as one pane).
      #   stack row 1 — db | search           (2 panes; db combines
      #     Postgres + Redis fenced by a hairline)
      #   stack row 2 — storage (single wide pane, no right cell)
      get settings_path
      expect(response.body.scan(/class="pane-row"/).length).to eq(6)
      panes = response.body.scan(/class="pane(?:\s[^"]*)?"/).size
      expect(panes).to eq(11)
    end

    it "separates the OAuth applications and tokens sub-sections with a hairline" do
      # The combined pane fences its two sections with a single
      # `<hr class="hairline">`. Asserting on the markup pins the
      # contract — without the hairline the pane reads as one blob.
      get settings_path
      expect(response.body).to include('<hr class="hairline">')
    end

    it "does not paint sections with inline pane-bg tokens (CSS handles zebra)" do
      get settings_path
      # The new system never references the bg tokens inline — zebra is a
      # CSS responsibility (`.pane:nth-child(even)`). Asserting absence
      # protects against regressions that re-introduce inline styling.
      expect(response.body).not_to include("var(--color-pane-bg-a)")
      expect(response.body).not_to include("var(--color-pane-bg-b)")
      expect(response.body).not_to include("var(--color-pane-bg-wide)")
    end

    # Phase B revamp (2026-05-05) — settings page goes edge-to-edge,
    # matching project show. No centered max-width wrapper.
    it "does not wrap the section stack in a centered max-width container" do
      get settings_path
      expect(response.body).not_to match(/max-width:\s*880px;\s*margin:\s*0 auto/)
    end

    # 2026-05-10 user-locked restructure — page is now three titled
    # sections, each a 2-column grid:
    #
    #   ## customize
    #   [ ui / ux ]              [ workspaces ]
    #   [ user ]                 [ time zone ]
    #
    #   ## integrations
    #   [ YouTube ]              [ Voyage.ai ]
    #   [ OAuth applications ]   [ sessions ]
    #
    #   ## stack
    #   [ sql ]                  [ search ]
    #   [ storage ]              (empty)
    #
    # DOM order pins the sequence: every pane h2 in each row appears
    # in left-to-right, top-to-bottom order. The OAuth pane's combined
    # `tokens` sub-section sits between OAuth applications and the
    # sessions pane (same row 2 of integrations, separated by a
    # `<hr class="hairline">`).
    it "orders the panes per the user-locked customize / integrations / stack layout" do
      get settings_path
      # customize
      idx_appearance = response.body.index('value="appearance"')
      idx_workspaces = response.body.index('value="workspaces"')
      idx_user       = response.body.index("<h2>user</h2>")
      idx_time_zone  = response.body.index("<h2>time zone</h2>")
      # integrations
      idx_youtube    = response.body.index("<h2>YouTube</h2>")
      idx_voyage     = response.body.index('value="voyage"')
      idx_oauth_apps = response.body.index("<h2>OAuth applications</h2>")
      idx_tokens     = response.body.index("<h2>tokens</h2>")
      idx_sessions   = response.body.index("<h2>sessions</h2>")
      # stack — 2026-05-11 (later) `sql` renamed to `db`; the Redis
      # block lives inside the `db` pane (no standalone heading).
      idx_db         = response.body.index("<h2>db</h2>")
      idx_search     = response.body.index("<h2>search</h2>")
      idx_storage    = response.body.index("<h2>storage</h2>")

      indices = [ idx_appearance, idx_workspaces, idx_user, idx_time_zone,
                  idx_youtube, idx_voyage, idx_oauth_apps, idx_tokens, idx_sessions,
                  idx_db, idx_search, idx_storage ]
      expect(indices).to all(be_a(Integer))
      expect(indices).to eq(indices.sort)
    end

    # 2026-05-10 user-locked restructure — three section headings
    # bracket the page. Headings are h2-styled and lowercase per
    # project convention.
    it "renders the three section headings in order: customize -> integrations -> stack" do
      get settings_path
      idx_customize    = response.body.index("<h2>customize</h2>")
      idx_integrations = response.body.index("<h2>integrations</h2>")
      idx_stack        = response.body.index("<h2>stack</h2>")
      expect([ idx_customize, idx_integrations, idx_stack ]).to all(be_a(Integer))
      expect(idx_customize).to be < idx_integrations
      expect(idx_integrations).to be < idx_stack
    end

    # 2026-05-10 — `sql`, `storage`, `search` panes carry connectivity
    # / presence copy. Asserting the headings + status copy pins the
    # stack section so a future ivar rename can't silently break it.
    # 2026-05-11 (later) — `sql` renamed to `db`; Redis demoted from a
    # standalone pane into a hairline-fenced row inside the `db`
    # pane. Storage gets a 2-column inner layout (`assets` + `notes`,
    # renamed from `pito-assets`) on a single wide pane.
    it "renders the stack section with db, search, storage panes" do
      get settings_path
      expect(response.body).to include("<h2>db</h2>")
      expect(response.body).to include("<h2>search</h2>")
      expect(response.body).to include("<h2>storage</h2>")
      # `sql` heading is gone (renamed).
      expect(response.body).not_to include("<h2>sql</h2>")
      # `redis` standalone heading is gone (folded into `db`).
      expect(response.body).not_to include("<h2>redis</h2>")
      # `db` pane surfaces both Postgres + Redis labels.
      expect(response.body).to include("Postgres")
      expect(response.body).to include(">Redis<")
      # `storage` pane covers BOTH assets AND notes columns.
      expect(response.body).to include(">assets<")
      expect(response.body).to include(">notes<")
      # `pito-assets` display label was renamed to `assets`; the
      # on-disk volume name still appears nowhere user-visible in
      # the storage pane.
      storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
      expect(storage_section).not_to be_nil
      expect(storage_section).not_to include("pito-assets")
    end

    # 2026-05-11 (later 2) — per user direction the Postgres half
    # drops version / database / total rows / total size on disk.
    # The status badge above the per-model breakdown table is the
    # only Postgres surface besides the table itself.
    describe "db pane Postgres lines dropped (later 2 refactor)" do
      it "does not render the version / database / rows / size-on-disk lines" do
        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        expect(db_section).not_to include("version:")
        expect(db_section).not_to include("database:")
        expect(db_section).not_to include("rows:")
        expect(db_section).not_to include("size on disk:")
      end
    end

    # 2026-05-11 (later 2) — per user direction the Meilisearch
    # half drops the flat `indexed documents` list and the
    # `total index size` summary. The new surface is a per-index
    # `index | documents | size` table sourced from
    # `Search.engine.per_index_stats`.
    describe "search pane per-index breakdown" do
      let(:engine) { instance_double(Search::MeilisearchEngine) }

      before do
        allow(Search).to receive(:engine).and_return(engine)
        allow(engine).to receive(:healthy?).and_return(true)
        allow(engine).to receive(:index_stats).and_return({})
      end

      it "renders a per-index table with documents + size columns" do
        allow(engine).to receive(:per_index_stats).and_return(
          "channels_development" => { documents: 12, size_bytes: 4_500_000 },
          "videos_development"   => { documents: 9_876, size_bytes: 50_000_000 }
        )
        get settings_path
        search_section = response.body[/<legend><h2>search<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(search_section).not_to be_nil
        # Headers.
        expect(search_section).to include(">index<")
        expect(search_section).to include(">documents<")
        expect(search_section).to include(">size<")
        # Display labels strip the env suffix.
        expect(search_section).to include(">channels<")
        expect(search_section).to include(">videos<")
        # number_with_delimiter on documents.
        expect(search_section).to include("9,876")
        # number_to_human_size on bytes — 50_000_000 → "47.7 MB" (binary).
        expect(search_section).to include("47.7 MB")
        # Right-alignment class on numeric cells.
        expect(search_section).to include('class="text-muted num"')
      end

      it "drops the flat 'indexed documents' list and the 'total index size' line" do
        allow(engine).to receive(:per_index_stats).and_return(
          "channels_development" => { documents: 12, size_bytes: 4_500_000 }
        )
        get settings_path
        search_section = response.body[/<legend><h2>search<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(search_section).not_to include("indexed documents")
        expect(search_section).not_to include("total index size")
      end

      it "hides the table when the engine returns no per-index stats" do
        allow(engine).to receive(:per_index_stats).and_return({})
        get settings_path
        search_section = response.body[/<legend><h2>search<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(search_section).not_to be_nil
        expect(search_section).not_to include(">documents<")
      end

      it "sorts rows by documents descending" do
        allow(engine).to receive(:per_index_stats).and_return(
          "channels_development" => { documents: 12,    size_bytes: 4_500_000 },
          "videos_development"   => { documents: 9_876, size_bytes: 50_000_000 },
          "projects_development" => { documents: 100,   size_bytes: 1_000_000 }
        )
        get settings_path
        search_section = response.body[/<legend><h2>search<\/h2><\/legend>.*?<\/fieldset>/m]
        order = %w[videos projects channels]
        positions = order.map { |label| search_section.index(">#{label}<") }
        expect(positions).to all(be_a(Integer))
        expect(positions).to eq(positions.sort)
      end

      # The Meilisearch + Voyage embeddings fence with a single
      # `<hr class="hairline">` survives the refactor.
      it "separates the Meilisearch and Voyage embeddings blocks with a hairline" do
        allow(engine).to receive(:per_index_stats).and_return({})
        get settings_path
        search_section = response.body[/<legend><h2>search<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(search_section).not_to be_nil
        expect(search_section).to include('<hr class="hairline">')
        idx_hairline = search_section.index('<hr class="hairline">')
        idx_voyage   = search_section.index("Voyage embeddings")
        expect(idx_hairline).to be < idx_voyage
      end
    end

    # 2026-05-11 (later) — Redis demoted from a standalone pane
    # into a hairline-fenced sub-section of the `db` pane. The
    # assertions scope to the `db` pane's fieldset instead of a
    # `redis` legend. (later 2) — version / memory / keys /
    # persistence lines dropped per user direction; only the
    # connectivity badge + Sidekiq breakdown survive.
    describe "db pane (Redis half)" do
      let(:redis_double) { instance_double(Redis) }

      it "renders the connected status badge without the dropped meta lines" do
        allow(Redis).to receive(:new).and_return(redis_double)
        allow(redis_double).to receive(:info).and_return(
          "redis_version" => "7.4.1",
          "used_memory_human" => "2.34M",
          "aof_enabled" => "0",
          "rdb_changes_since_last_save" => "0"
        )
        allow(redis_double).to receive(:dbsize).and_return(42)
        allow(redis_double).to receive(:close)

        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        expect(db_section).to include(">Redis<")
        expect(db_section).to include("▲ connected")
        redis_idx = db_section.index(">Redis<")
        redis_half = db_section[redis_idx..]
        # The four dropped meta lines never render.
        expect(redis_half).not_to include("version:")
        expect(redis_half).not_to include("memory:")
        expect(redis_half).not_to include("keys:")
        expect(redis_half).not_to include("persistence:")
      end

      it "flips to disconnected on Redis::CannotConnectError without 500ing the page" do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError.new("nope"))
        get settings_path
        expect(response).to have_http_status(:ok)
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        # Find the substring AFTER the Redis label so we don't
        # accidentally match the Postgres "▲ connected" line above.
        redis_idx = db_section.index(">Redis<")
        redis_half = db_section[redis_idx..]
        expect(redis_half).to include("▽ disconnected")
      end

      it "flips to disconnected on a generic StandardError (defensive rescue)" do
        allow(Redis).to receive(:new).and_raise(StandardError.new("kaboom"))
        get settings_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<h2>db</h2>")
        # The Redis half flips to ▽ disconnected.
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        redis_idx = db_section.index(">Redis<")
        redis_half = db_section[redis_idx..]
        expect(redis_half).to include("▽ disconnected")
      end

      # 2026-05-11 (later) — the `db` pane fences the Postgres
      # block (top) and the Redis block (bottom) with a single
      # `<hr class="hairline">`, mirroring the Meilisearch /
      # Voyage embeddings fence in the `search` pane.
      it "separates the Postgres and Redis blocks with a hairline" do
        allow(Redis).to receive(:new).and_return(redis_double)
        allow(redis_double).to receive(:info).and_return(
          "redis_version" => "7.4.1", "used_memory_human" => "1.00M",
          "aof_enabled" => "0", "rdb_changes_since_last_save" => "0"
        )
        allow(redis_double).to receive(:dbsize).and_return(0)
        allow(redis_double).to receive(:close)

        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        expect(db_section).to include('<hr class="hairline">')
        idx_hairline = db_section.index('<hr class="hairline">')
        idx_redis    = db_section.index(">Redis<")
        expect(idx_hairline).to be < idx_redis
      end
    end

    describe "storage pane volumes" do
      it "renders both assets and notes columns with size + file count" do
        # `Pito::AssetsRoot.root` returns a Pathname under
        # `Rails.root/tmp/...` in dev/test. `notes_volume_status_for_settings_pane`
        # walks `docs/notes/`. Stub the filesystem so the test
        # doesn't depend on whatever happens to be on disk.
        assets_path = Rails.root.join("tmp/spec-pito-assets")
        notes_path = Rails.root.join("docs/notes")
        allow(Pito::AssetsRoot).to receive(:root).and_return(assets_path)
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(assets_path).and_return(true)
        allow(File).to receive(:directory?).with(assets_path.to_s).and_return(true)
        allow(File).to receive(:directory?).with(notes_path).and_return(true)
        allow(File).to receive(:writable?).and_call_original
        allow(File).to receive(:writable?).with(assets_path).and_return(true)
        allow(File).to receive(:writable?).with(notes_path).and_return(true)
        allow(Dir).to receive(:children).with(assets_path.to_s).and_return([])
        allow(Dir).to receive(:glob).and_call_original
        allow(Dir).to receive(:glob)
          .with(File.join(assets_path.to_s, "**", "*"), File::FNM_DOTMATCH)
          .and_return([ "#{assets_path}/a.bin", "#{assets_path}/b.bin" ])
        allow(Dir).to receive(:glob)
          .with(File.join(notes_path.to_s, "**", "*"), File::FNM_DOTMATCH)
          .and_return([ "#{notes_path}/note-1.md" ])
        allow(File).to receive(:file?).and_call_original
        allow(File).to receive(:file?).with("#{assets_path}/a.bin").and_return(true)
        allow(File).to receive(:file?).with("#{assets_path}/b.bin").and_return(true)
        allow(File).to receive(:file?).with("#{notes_path}/note-1.md").and_return(true)
        allow(File).to receive(:size).and_call_original
        allow(File).to receive(:size).with("#{assets_path}/a.bin").and_return(1_000_000)
        allow(File).to receive(:size).with("#{assets_path}/b.bin").and_return(500_000)
        allow(File).to receive(:size).with("#{notes_path}/note-1.md").and_return(2_048)
        # Bypass Rails.cache so the stubs are exercised on every call.
        allow(Rails.cache).to receive(:fetch).and_yield

        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to be_nil
        # Both column labels are present.
        expect(storage_section).to include(">assets<")
        expect(storage_section).to include(">notes<")
        # The `pito-assets` legacy label is gone from the user-
        # visible surface (display label only — env var stays).
        expect(storage_section).not_to include("pito-assets")
        # Both columns report writable.
        expect(storage_section.scan("▲ writable").size).to eq(2)
        # File counts render via `number_with_delimiter`.
        expect(storage_section).to include("files: 2")
        expect(storage_section).to include("files: 1")
      end

      it "no longer renders the path: line (user direction 2026-05-11)" do
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to be_nil
        expect(storage_section).not_to match(/path:\s*<code>/)
      end

      it "drops the marketing tagline ('on-disk home for footage thumbnails ...')" do
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to include("on-disk home for footage thumbnails")
      end

      it "renders ▽ not present + no stats when the assets volume is absent" do
        absent = Rails.root.join("tmp/definitely-not-here-#{SecureRandom.hex(4)}")
        allow(Pito::AssetsRoot).to receive(:root).and_return(absent)
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).to include(">assets<")
        expect(storage_section).to include("▽ not present")
      end
    end

    # 2026-05-11 (later) — Postgres per-model breakdown table inside
    # the `db` pane. Sorted by on-disk size DESC. (later 2) header
    # column renamed from `table` to `model`; numeric cells right-
    # align via `class="num"`.
    describe "db pane Postgres per-model breakdown" do
      it "renders a 6-row table with the domain models when connected" do
        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        # Header row uses `model` (renamed from `table` in later 2).
        expect(db_section).to include(">model<")
        expect(db_section).to include(">rows<")
        expect(db_section).to include(">size<")
        # The numeric headers + cells carry the `.num` right-align class.
        expect(db_section).to include('class="num"')
        expect(db_section).to include('class="text-muted num"')
        # Each of the six tables surfaces by its literal table name.
        %w[channels videos projects games notifications calendar_entries].each do |table|
          expect(db_section).to include(">#{table}<")
        end
      end

      it "sorts rows by on-disk size descending" do
        # Stub the per-table query so the size order is deterministic.
        allow(Rails.cache).to receive(:fetch).and_call_original
        allow_any_instance_of(SettingsController)
          .to receive(:compute_postgres_table_stats) do |_ctrl, table, _class|
            sizes = {
              "channels"         => 1_000,
              "videos"           => 9_000_000,
              "projects"         => 2_000,
              "games"            => 50_000,
              "notifications"    => 200_000,
              "calendar_entries" => 7_000
            }
            { count: 1, size_bytes: sizes[table] }
          end

        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        order = %w[videos notifications games calendar_entries projects channels]
        positions = order.map { |t| db_section.index(">#{t}<") }
        expect(positions).to all(be_a(Integer))
        expect(positions).to eq(positions.sort)
      end

      it "omits the breakdown table when the per-model query raises (pane still renders)" do
        # Make the inner table-stats helper raise. Both layers
        # (postgres_table_stats and postgres_table_breakdown_for_settings_pane)
        # carry an outer `rescue StandardError`; the result is an
        # empty array, and the view skips the table block.
        allow_any_instance_of(SettingsController)
          .to receive(:compute_postgres_table_stats)
          .and_raise(ActiveRecord::StatementInvalid.new("boom"))
        get settings_path
        expect(response).to have_http_status(:ok)
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        # No table header — the breakdown block is skipped entirely.
        expect(db_section).not_to include(">model<")
        expect(db_section).not_to include(">channels<")
      end
    end

    # 2026-05-11 (later 2) — Sidekiq breakdown rebuilt as a 3-row
    # grouped-header layout per user direction:
    #   row 1 (thead) — `successful` (colspan 3) | `failed` (colspan 2)
    #   row 2 (thead) — totals for each header
    #   row 3 (thead) — busy | scheduled | enqueued | retry | dead
    #   row 4 (tbody) — five live state counts
    # All numeric cells right-align via `class="num"`.
    describe "db pane Sidekiq breakdown" do
      let(:redis_double) { instance_double(Redis) }

      before do
        allow(Redis).to receive(:new).and_return(redis_double)
        allow(redis_double).to receive(:info).and_return(
          "redis_version" => "7.4.1", "used_memory_human" => "1.00M",
          "aof_enabled" => "0", "rdb_changes_since_last_save" => "0"
        )
        allow(redis_double).to receive(:dbsize).and_return(0)
        allow(redis_double).to receive(:close)
      end

      it "renders the 2-group grouped header (successful spans 3, failed spans 2)" do
        stats = instance_double(Sidekiq::Stats,
          processed: 14_145, failed: 7_845, enqueued: 7,
          scheduled_size: 2, retry_size: 1, dead_size: 256
        )
        allow(Sidekiq::Stats).to receive(:new).and_return(stats)
        workers = instance_double(Sidekiq::Workers, size: 3)
        allow(Sidekiq::Workers).to receive(:new).and_return(workers)

        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        # Grouped headers with colspan attributes.
        expect(db_section).to include('colspan="3"')
        expect(db_section).to include('colspan="2"')
        expect(db_section).to match(/<th[^>]*colspan="3"[^>]*>successful<\/th>/)
        expect(db_section).to match(/<th[^>]*colspan="2"[^>]*>failed<\/th>/)
        # Totals row sits between the grouped header and the 5-column
        # state header; the totals carry the .num class.
        expect(db_section).to match(/<td[^>]*colspan="3"[^>]*>\s*14,145/)
        expect(db_section).to match(/<td[^>]*colspan="2"[^>]*>\s*7,845/)
      end

      it "renders the 5 state columns in lifecycle order with right-aligned counts" do
        stats = instance_double(Sidekiq::Stats,
          processed: 14_145, failed: 7_845, enqueued: 99,
          scheduled_size: 2, retry_size: 4, dead_size: 256
        )
        allow(Sidekiq::Stats).to receive(:new).and_return(stats)
        workers = instance_double(Sidekiq::Workers, size: 0)
        allow(Sidekiq::Workers).to receive(:new).and_return(workers)

        get settings_path
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        # Five state column headers in lifecycle order.
        order = %w[busy scheduled enqueued retry dead]
        positions = order.map { |s| db_section.index(">#{s}<") }
        expect(positions).to all(be_a(Integer))
        expect(positions).to eq(positions.sort)
        # Right-aligned numeric cells.
        expect(db_section).to include('class="text-muted num"')
        # The dead count renders via number_with_delimiter.
        expect(db_section).to include("256")
        # The old single-cell `sidekiq` header is gone (grouped layout).
        expect(db_section).not_to include(">sidekiq<")
      end

      it "swallows a Sidekiq::Stats failure (table absent, pane still renders)" do
        allow(Sidekiq::Stats).to receive(:new).and_raise(Redis::CannotConnectError.new("nope"))
        get settings_path
        expect(response).to have_http_status(:ok)
        db_section = response.body[/<legend><h2>db<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(db_section).not_to be_nil
        # No grouped header — controller swallowed the error and
        # the view skipped the block entirely.
        expect(db_section).not_to include(">successful<")
        expect(db_section).not_to include(">failed<")
      end
    end

    # 2026-05-11 (later) — `storage` pane 2-column inner layout.
    # `assets` (left) + `notes` (right) separated by a vertical
    # hairline gutter. Both columns carry their own
    # per-subcategory breakdown table.
    describe "storage pane 2-column layout" do
      it "renders a vertical hairline gutter between the two columns" do
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to be_nil
        # The gutter is a 1px-wide column painted with the border
        # color; the spec pins the unique style fragment that
        # describes it.
        expect(storage_section).to include("background: var(--color-border); width: 1px;")
      end

      it "uses .pane--wide so the inner grid has room for both tables" do
        get settings_path
        # The storage pane is the only .pane--wide on the page.
        expect(response.body).to match(/<div class="pane pane--wide">\s*<fieldset[^>]*>\s*<legend><h2>storage<\/h2><\/legend>/m)
      end

      it "places assets BEFORE notes in DOM order (left → right)" do
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        idx_assets = storage_section.index(">assets<")
        idx_notes  = storage_section.index(">notes<")
        expect(idx_assets).to be < idx_notes
      end
    end

    # 2026-05-11 (later) — `assets` column per-subcategory
    # breakdown table. User direction (follow-up): "no need for
    # split. Just major assets type: cover arts, thumbnails,
    # banners..." The breakdown is now a fixed 4-row allowlist:
    #   * cover arts — `composites/`
    #   * thumbnails — `footage_thumbs/`
    #   * banners    — `banners/` (reserved; may not exist yet)
    #   * other      — everything else, including Active Storage's
    #                  2-char-prefix shard directories
    # All four rows always render — even at 0 files / 0 bytes —
    # so the operator sees the full asset taxonomy.
    describe "assets column breakdown table" do
      it "renders the four allowlisted category labels in fixed order" do
        allow_any_instance_of(SettingsController)
          .to receive(:assets_breakdown_for_settings_pane)
          .and_return([
            { label: "cover arts", file_count: 200,    size_bytes: 50_000_000 },
            { label: "thumbnails", file_count: 12_345, size_bytes: 4_500_000_000 },
            { label: "banners",    file_count: 0,      size_bytes: 0 },
            { label: "other",      file_count: 30,     size_bytes: 3_000_000 }
          ])

        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to be_nil
        # Header row.
        expect(storage_section).to include(">category<")
        # All four allowlisted labels.
        expect(storage_section).to include(">cover arts<")
        expect(storage_section).to include(">thumbnails<")
        expect(storage_section).to include(">banners<")
        expect(storage_section).to include(">other<")
        # File counts via `number_with_delimiter`.
        expect(storage_section).to include("12,345")
        # Controller's contract: rows render in the order it
        # returns them (allowlist order: cover arts → thumbnails
        # → banners → other).
        order = [ "cover arts", "thumbnails", "banners", "other" ]
        positions = order.map { |label| storage_section.index(">#{label}<") }
        expect(positions).to all(be_a(Integer))
        expect(positions).to eq(positions.sort)
      end

      it "renders the four-row table even when the assets root is absent" do
        # Stub the resolved root to a non-existent path so the
        # controller takes the `assets_breakdown_empty` branch.
        Dir.mktmpdir do |tmp|
          ghost = File.join(tmp, "does-not-exist")
          allow(Pito::AssetsRoot).to receive(:root).and_return(Pathname.new(ghost))
          get settings_path
          storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
          expect(storage_section).not_to be_nil
          # All four rows still render at 0 / 0 so the operator
          # sees the asset taxonomy on a greenfield install.
          expect(storage_section).to include(">category<")
          expect(storage_section).to include(">cover arts<")
          expect(storage_section).to include(">thumbnails<")
          expect(storage_section).to include(">banners<")
          expect(storage_section).to include(">other<")
        end
      end

      # Regression — Active Storage's 2-char-prefix shard
      # directories used to surface as their raw names (`iz`,
      # `m4`, `7a`, `47`, `w2`, ...). The allowlist refactor
      # collapses them into a single `other` row that preserves
      # total bytes / file count.
      it "folds Active-Storage-style shard directories into `other`" do
        Dir.mktmpdir do |tmp|
          assets_root = Pathname.new(tmp)
          # Three named categories — one populated, two empty.
          FileUtils.mkdir_p(assets_root.join("composites"))
          File.write(assets_root.join("composites/cover.png"), "a" * 100)
          FileUtils.mkdir_p(assets_root.join("footage_thumbs"))
          # `banners` directory absent — should still surface at 0/0.
          # Active Storage shard layout: `<2char>/<2char>/<hash>`.
          %w[iz m4 7a 47 w2 gl fq].each do |shard|
            blob_dir = assets_root.join(shard, "ab")
            FileUtils.mkdir_p(blob_dir)
            File.write(blob_dir.join("blob-#{shard}"), "x" * 50)
          end

          allow(Pito::AssetsRoot).to receive(:root).and_return(assets_root)
          Rails.cache.clear

          get settings_path
          storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
          # No raw shard names leak.
          %w[iz m4 7a 47 w2 gl fq].each do |shard|
            expect(storage_section).not_to include(">#{shard}<")
          end
          # All four allowlisted rows render.
          expect(storage_section).to include(">cover arts<")
          expect(storage_section).to include(">thumbnails<")
          expect(storage_section).to include(">banners<")
          expect(storage_section).to include(">other<")
        end
      end

      # Controller-level regression for the aggregation logic.
      # Hits the real `compute_assets_breakdown` against a tmp
      # tree so we lock down the math, not just the rendering.
      it "aggregates shard directories into a single `other` row at the controller level" do
        Dir.mktmpdir do |tmp|
          assets_root = Pathname.new(tmp)
          FileUtils.mkdir_p(assets_root.join("composites"))
          File.write(assets_root.join("composites/cover.png"), "a" * 100)
          # Seven shard dirs, 50 bytes each — `other` total 350.
          %w[iz m4 7a 47 w2 gl fq].each do |shard|
            FileUtils.mkdir_p(assets_root.join(shard))
            File.write(assets_root.join("#{shard}/blob"), "x" * 50)
          end

          controller = SettingsController.new
          rows = controller.send(:compute_assets_breakdown, assets_root)

          # Exactly 4 rows in allowlist order.
          expect(rows.map { |r| r[:label] }).to eq(
            [ "cover arts", "thumbnails", "banners", "other" ]
          )
          # Cover arts: one 100-byte file.
          cover = rows.find { |r| r[:label] == "cover arts" }
          expect(cover[:file_count]).to eq(1)
          expect(cover[:size_bytes]).to eq(100)
          # Thumbnails: empty (no `footage_thumbs/` dir on disk).
          thumbs = rows.find { |r| r[:label] == "thumbnails" }
          expect(thumbs[:file_count]).to eq(0)
          expect(thumbs[:size_bytes]).to eq(0)
          # Banners: empty (reserved).
          banners = rows.find { |r| r[:label] == "banners" }
          expect(banners[:file_count]).to eq(0)
          expect(banners[:size_bytes]).to eq(0)
          # Other: seven shard dirs aggregated.
          other = rows.find { |r| r[:label] == "other" }
          expect(other[:file_count]).to eq(7)
          expect(other[:size_bytes]).to eq(7 * 50)
        end
      end
    end

    # 2026-05-11 (later) — `notes` column per-namespace
    # breakdown table. Today: project notes (Note rows) + mobile
    # notes (docs/notes/). Future video / channel notes slot in
    # via `NOTES_NAMESPACE_SOURCES` in the controller.
    describe "notes column breakdown table" do
      it "renders both namespaces with count + size" do
        allow_any_instance_of(SettingsController)
          .to receive(:notes_breakdown_for_settings_pane)
          .and_return([
            { label: "project notes", count: 42, size_bytes: 5_000_000 },
            { label: "mobile notes",  count: nil, size_bytes: 1_024 }
          ])

        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to be_nil
        # Header row + the `count` column.
        expect(storage_section).to include(">namespace<")
        expect(storage_section).to include(">count<")
        # Both rows.
        expect(storage_section).to include(">project notes<")
        expect(storage_section).to include(">mobile notes<")
        # Project notes report a real count.
        expect(storage_section).to include("42")
        # Mobile notes (count nil) render an em-dash placeholder.
        expect(storage_section).to include("—")
      end

      it "renders no breakdown table when the controller returns []" do
        allow_any_instance_of(SettingsController)
          .to receive(:notes_breakdown_for_settings_pane)
          .and_return([])
        get settings_path
        storage_section = response.body[/<legend><h2>storage<\/h2><\/legend>.*?<\/fieldset>/m]
        expect(storage_section).not_to include(">namespace<")
      end
    end

    # 2026-05-10 — Slack / Discord panes were dropped from the
    # /settings index page per the user-locked layout. Their
    # controllers, routes, and partials remain — but the index no
    # longer renders them.
    it "does not render the Slack or Discord panes on the index" do
      get settings_path
      expect(response.body).not_to include("<h2>Slack</h2>")
      expect(response.body).not_to include("<h2>Discord</h2>")
    end

    it "renders the tokens pane with a link to /settings/tokens" do
      get settings_path
      expect(response.body).to include("<h2>tokens</h2>")
      expect(response.body).to include(settings_tokens_path)
    end

    # Phase 24 — brand casing for the surfaces that survive on the
    # Settings page. Google card moved to /channels; YouTube returned
    # 2026-05-10 as a read-only credentials STATUS card (not a form);
    # Voyage.ai and OAuth-applications carry brand casing as well.
    it "uses brand casing for YouTube, Voyage.ai and OAuth applications" do
      get settings_path
      expect(response.body).not_to include("<h2>Google</h2>")
      expect(response.body).to include("<h2>YouTube</h2>")
      expect(response.body).to include("<h2>Voyage.ai</h2>")
      expect(response.body).to include("<h2>OAuth applications</h2>")
    end

    # Phase 12 polish — search section heading drops the "engine" word.
    it "labels the search pane simply 'search' (no 'engine' suffix)" do
      get settings_path
      expect(response.body).to include("<h2>search</h2>")
      expect(response.body).not_to include("<h2>search engine</h2>")
    end

    # Phase 24 — YouTube client secret masking specs retired (form
    # gone with the rest of the Google/YouTube card).

    # Phase 12 polish — compact prose pattern. Counts read as terse
    # one-line sentences ("1 active token" / "10 active tokens" /
    # "no active tokens"), not a big number followed by a label.
    it "renders the tokens count as compact prose (singular)" do
      get settings_path # signs in default user via support/auth.rb
      ApiToken.delete_all
      ApiToken.generate!(user: User.first, name: "t1", scopes: [ Scopes::APP ])
      get settings_path
      expect(response.body).to include("1 active token")
    end

    it "renders the tokens count as compact prose (zero state)" do
      ApiToken.delete_all
      get settings_path
      expect(response.body).to include("no active tokens")
    end

    it "joins active and revoked token counts with a middle dot when both exist" do
      get settings_path # signs in default user
      ApiToken.delete_all
      ApiToken.generate!(user: User.first, name: "live", scopes: [ Scopes::APP ])
      revoked, _plaintext = ApiToken.generate!(user: User.first, name: "old", scopes: [ Scopes::APP ])
      revoked.revoke!
      get settings_path
      # Look for the "1 active · 1 revoked" shape (middle dot).
      expect(response.body).to match(/\d+ active\s+·\s+\d+ revoked/)
    end

    it "renders the sessions count as compact prose (singular)" do
      # The auto-sign-in helper mints exactly one Session row for the
      # default user, so the singular form is the natural state of a
      # request spec.
      get settings_path
      expect(response.body).to include("1 active session")
    end

    it "renders the OAuth applications count as compact prose (zero state)" do
      OauthApplication.delete_all if defined?(OauthApplication)
      get settings_path
      expect(response.body).to include("no OAuth applications")
    end
  end

  # Phase 24 — Google pane is gone. The describe block below is a
  # negative-guard sweep confirming the surface stays gone (no
  # `<h2>Google</h2>`, no `connected: yes/no`, no `channels:` block).
  describe "GET /settings — Google pane is gone (Phase 24 negative guards)" do
    let(:user) { User.first }
    let(:valid_url) do
      ->(i) {
        suffix = ("a".."z").to_a[i].to_s * 22
        "https://www.youtube.com/channel/UC#{suffix[0, 22]}"
      }
    end

    it "does not render `<h2>Google</h2>` whether or not connections exist" do
      get settings_path
      expect(response.body).not_to include("<h2>Google</h2>")

      create(:youtube_connection, user: user)
      get settings_path
      expect(response.body).not_to include("<h2>Google</h2>")
    end

    it "does not render `connected: yes/no` copy" do
      get settings_path
      expect(response.body).not_to include("connected: no")
      expect(response.body).not_to include("connected: yes")
    end

    it "does not render the legacy `channels:` aggregated list" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      title: "Catalin Ilinca",
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).not_to include("<li>Catalin Ilinca</li>")
      # The legacy bullet-style `channels:` header is gone too.
      expect(response.body).not_to match(/<p[^>]*>channels:<\/p>/)
    end

    it "does not render the `[manage]` link that pointed at /settings/youtube" do
      get settings_path
      expect(response.body).not_to match(%r{href="/settings/youtube"})
    end
  end

  # Phase 24 — `/settings/youtube` is gone; the URL 301-redirects to
  # /channels for back-compat (locked decision #1, retained indefinitely).
  describe "GET /settings/youtube (back-compat redirect)" do
    it "returns 301 Moved Permanently with Location: /channels" do
      get "/settings/youtube"
      expect(response).to have_http_status(:moved_permanently)
      # Rails' routing redirect synthesizes the full host; assert the
      # path component.
      expect(URI.parse(response.headers["Location"]).path).to eq("/channels")
    end
  end

  # Retired: legacy Google pane describe block. The body has been
  # converted to negative guards above. The describe below is left
  # intentionally short so future maintenance work doesn't accidentally
  # re-introduce the Google card.
  describe "GET /settings — legacy Google card retirement" do
    let(:user) { User.first }

    it "renders 200 even when YoutubeConnection rows exist (no Google card)" do
      create(:youtube_connection, user: user)
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<h2>Google</h2>")
    end
  end

  describe "PATCH /settings" do
    # Phase 24 — youtube_client_id / youtube_client_secret /
    # youtube_redirect_uri keys are not persisted by the settings form
    # any longer. The legacy fall-through path (`update_legacy`) leaves
    # them untouched. The PATCH path still accepts general + appearance
    # + voyage sections; the rest of the legacy PATCH specs below
    # exercise those.

    it "redirects to /settings after a section-less submit" do
      patch settings_path, params: {
        settings: { youtube_client_id: "noop" }
      }
      expect(response).to redirect_to(settings_path)
    end

    it "shows flash notice after save" do
      patch settings_path, params: {
        settings: { theme: "light" }
      }
      follow_redirect!
      expect(response.body).to include("settings saved.")
    end
  end

  # Phase B refinement (2026-05-04) — per-fieldset submits. Each fieldset has
  # its own form with a hidden `section` field. PATCH-ing a single section
  # MUST NOT touch fields that belong to other sections.
  describe "PATCH /settings (per-section submits)" do
    it "workspaces section saves only general keys, leaves theme alone" do
      AppSetting.set("theme", "dark")
      patch settings_path, params: {
        section: "workspaces",
        settings: { pane_title_length: "20", max_panes: "7" }
      }
      expect(AppSetting.get("pane_title_length")).to eq("20")
      expect(AppSetting.get("max_panes")).to eq("7")
      expect(AppSetting.get("theme")).to eq("dark")
    end

    it "appearance section saves only the theme, leaves general alone" do
      AppSetting.set("max_panes", "9")
      patch settings_path, params: {
        section: "appearance",
        settings: { theme: "light" }
      }
      expect(AppSetting.get("theme")).to eq("light")
      expect(AppSetting.get("max_panes")).to eq("9")
    end

    # 2026-05-11 — keyboard-navigation toggle is persisted by the same
    # `appearance` section form that owns the theme picker. yes/no
    # strings on the wire per the project's external-boolean rule;
    # internal storage stays Boolean.
    describe "keyboard_navigation_enabled persistence" do
      it "persists 'no' on the singleton AppSetting row" do
        patch settings_path, params: {
          section: "appearance",
          settings: { theme: "dark", keyboard_navigation_enabled: "no" }
        }
        expect(AppSetting.keyboard_navigation_enabled?).to be(false)
      end

      it "subsequent GET reflects the off state via the checked radio" do
        patch settings_path, params: {
          section: "appearance",
          settings: { keyboard_navigation_enabled: "no" }
        }
        get settings_path
        expect(response.body).to match(/<input type="radio" name="settings\[keyboard_navigation_enabled\]" value="no"[^>]*\bchecked\b/)
      end

      it "flips back to 'yes' on a subsequent submit" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(keyboard_navigation_enabled: false)
        patch settings_path, params: {
          section: "appearance",
          settings: { keyboard_navigation_enabled: "yes" }
        }
        expect(AppSetting.keyboard_navigation_enabled?).to be(true)
      end

      it "saves theme + keyboard_navigation_enabled together in one submit" do
        patch settings_path, params: {
          section: "appearance",
          settings: { theme: "dark", keyboard_navigation_enabled: "no" }
        }
        expect(AppSetting.get("theme")).to eq("dark")
        expect(AppSetting.keyboard_navigation_enabled?).to be(false)
      end

      it "ignores values other than 'yes' / 'no' (Boolean true rejected)" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(keyboard_navigation_enabled: true)
        patch settings_path, params: {
          section: "appearance",
          settings: { keyboard_navigation_enabled: "true" }
        }
        # "true" is not "yes"; flag is left at the prior value.
        expect(AppSetting.keyboard_navigation_enabled?).to be(true)
      end

      it "bootstraps an AppSetting row when the table is empty" do
        AppSetting.delete_all
        patch settings_path, params: {
          section: "appearance",
          settings: { keyboard_navigation_enabled: "no" }
        }
        expect(AppSetting.keyboard_navigation_enabled?).to be(false)
      end

      it "leaves keyboard_navigation_enabled alone when only theme is submitted" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(keyboard_navigation_enabled: false)
        patch settings_path, params: {
          section: "appearance",
          settings: { theme: "light" }
        }
        expect(AppSetting.keyboard_navigation_enabled?).to be(false)
      end
    end

    # Phase 24 — `youtube_oauth` section was dropped along with the
    # Google card. Submitting `section=youtube_oauth` falls through to
    # `update_legacy`, which silently no-ops on the dropped keys.
    it "youtube_oauth section is a no-op (Phase 24 — dropped)" do
      AppSetting.set("max_panes", "9")
      AppSetting.set("theme", "dark")
      patch settings_path, params: {
        section: "youtube_oauth",
        settings: {
          youtube_client_id: "new-id",
          youtube_client_secret: "new-secret",
          youtube_redirect_uri: "http://example.test/cb"
        }
      }
      # Whatever the AppSetting helper does internally with arbitrary
      # keys is outside this phase — the contract is that the surface
      # is gone, not that the keys actively reject.
      expect(response).to redirect_to(settings_path)
      expect(AppSetting.get("max_panes")).to eq("9")
      expect(AppSetting.get("theme")).to eq("dark")
    end

    # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — voyage section now accepts
    # a key + per-target flag. The model validation enforces that flipping
    # the flag on requires a non-blank key; clearing the key while the flag
    # is on fails. yes/no boundary strings still apply on the flag.

    it "voyage section saves the API key + flag together" do
      AppSetting.set("max_panes", "5")
      patch settings_path, params: {
        section: "voyage",
        settings: {
          voyage_api_key: "vk_my_real_key",
          voyage_index_project_notes: "yes"
        }
      }
      AppSetting.first.reload
      expect(AppSetting.voyage_configured?).to be(true)
      expect(AppSetting.first.voyage_api_key).to eq("vk_my_real_key")
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "voyage section rejects flag=yes when no key is configured" do
      AppSetting.set("max_panes", "5")
      patch settings_path, params: {
        section: "voyage",
        settings: { voyage_index_project_notes: "yes" }
      }
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
      expect(flash[:alert]).to include("Voyage API key required")
    end

    it "voyage section leaves an existing key untouched when input is blank" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(voyage_api_key: "vk_existing")
      patch settings_path, params: {
        section: "voyage",
        settings: { voyage_api_key: "", voyage_index_project_notes: "no" }
      }
      expect(AppSetting.first.reload.voyage_api_key).to eq("vk_existing")
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end

    it "voyage section ignores flag values other than 'yes' / 'no'" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk", voyage_index_project_notes: true
      )
      patch settings_path, params: {
        section: "voyage",
        settings: { voyage_index_project_notes: "true" }
      }
      # Boolean "true" is not "yes" — the boundary rule rejects it; flag is
      # left untouched.
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "voyage section clears the key when clear_voyage_api_key=yes and flag is off" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk_to_clear", voyage_index_project_notes: false
      )
      patch settings_path, params: {
        section: "voyage",
        settings: { clear_voyage_api_key: "yes" }
      }
      expect(AppSetting.first.reload.voyage_api_key).to be_nil
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end

    it "voyage section refuses to clear the key while flag is on" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk_protected", voyage_index_project_notes: true
      )
      patch settings_path, params: {
        section: "voyage",
        settings: { clear_voyage_api_key: "yes" }
      }
      expect(AppSetting.first.reload.voyage_api_key).to eq("vk_protected")
      expect(flash[:alert]).to include("Voyage API key required")
    end

    it "voyage section bootstraps an AppSetting row when the table is empty" do
      AppSetting.delete_all
      patch settings_path, params: {
        section: "voyage",
        settings: {
          voyage_api_key: "vk_bootstrap",
          voyage_index_project_notes: "yes"
        }
      }
      expect(AppSetting.voyage_configured?).to be(true)
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "GET /settings does not leak the plaintext API key in the response body" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk_super_secret_plaintext",
        voyage_index_project_notes: true
      )
      get settings_path
      expect(response.body).not_to include("vk_super_secret_plaintext")
    end

    # 2026-05-11 — YouTube credentials section. Mirrors the Voyage
    # tests above. Blank input keeps the current value; explicit
    # `clear_youtube_<field>: "yes"` wipes a field; the table is
    # bootstrapped when empty.
    describe "section=youtube" do
      it "saves all four fields together (happy path)" do
        AppSetting.delete_all
        patch settings_path, params: {
          section: "youtube",
          settings: {
            youtube_api_key:       "AIza_real_api_key",
            youtube_client_id:     "123-abc.apps.googleusercontent.com",
            youtube_client_secret: "GOCSPX-real_secret",
            youtube_redirect_uri:  "https://example.test/auth/google/callback"
          }
        }
        expect(response).to redirect_to(settings_path)
        row = AppSetting.first
        expect(row.youtube_api_key).to       eq("AIza_real_api_key")
        expect(row.youtube_client_id).to     eq("123-abc.apps.googleusercontent.com")
        expect(row.youtube_client_secret).to eq("GOCSPX-real_secret")
        expect(row.youtube_redirect_uri).to  eq("https://example.test/auth/google/callback")
      end

      it "leaves an existing field untouched when its input is blank" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(
          youtube_api_key: "k_existing_api",
          youtube_client_id: "k_existing_id"
        )
        patch settings_path, params: {
          section: "youtube",
          settings: {
            youtube_api_key: "",
            youtube_client_id: ""
          }
        }
        row = AppSetting.first.reload
        expect(row.youtube_api_key).to   eq("k_existing_api")
        expect(row.youtube_client_id).to eq("k_existing_id")
      end

      it "clears a field when clear_youtube_<field>=yes" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(
          youtube_api_key: "k_to_clear",
          youtube_client_secret: "k_keep"
        )
        patch settings_path, params: {
          section: "youtube",
          settings: { clear_youtube_api_key: "yes" }
        }
        row = AppSetting.first.reload
        expect(row.youtube_api_key).to       be_nil
        expect(row.youtube_client_secret).to eq("k_keep")
      end

      it "wipes all four fields when every clear flag is yes" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(
          youtube_api_key: "a",
          youtube_client_id: "b",
          youtube_client_secret: "c",
          youtube_redirect_uri: "d"
        )
        patch settings_path, params: {
          section: "youtube",
          settings: {
            clear_youtube_api_key:       "yes",
            clear_youtube_client_id:     "yes",
            clear_youtube_client_secret: "yes",
            clear_youtube_redirect_uri:  "yes"
          }
        }
        row = AppSetting.first.reload
        expect(row.youtube_api_key).to       be_nil
        expect(row.youtube_client_id).to     be_nil
        expect(row.youtube_client_secret).to be_nil
        expect(row.youtube_redirect_uri).to  be_nil
      end

      it "bootstraps an AppSetting row when the table is empty" do
        AppSetting.delete_all
        patch settings_path, params: {
          section: "youtube",
          settings: { youtube_api_key: "k_bootstrap" }
        }
        expect(AppSetting.count).to eq(1)
        expect(AppSetting.first.youtube_api_key).to eq("k_bootstrap")
      end

      it "redirects with a success notice on save" do
        AppSetting.delete_all
        patch settings_path, params: {
          section: "youtube",
          settings: { youtube_api_key: "k" }
        }
        expect(response).to redirect_to(settings_path)
        follow_redirect!
        expect(response.body).to include("settings saved.")
      end

      it "is a no-op when no input changes (no params, no clear flags)" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(youtube_api_key: "k_keep")
        patch settings_path, params: { section: "youtube", settings: {} }
        expect(AppSetting.first.reload.youtube_api_key).to eq("k_keep")
      end

      it "GET /settings does not leak the plaintext youtube_api_key in the response body" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(
          youtube_api_key: "AIza_super_secret_plaintext_42"
        )
        get settings_path
        expect(response.body).not_to include("AIza_super_secret_plaintext_42")
      end

      it "GET /settings does not leak the plaintext youtube_client_secret in the response body" do
        AppSetting.set("max_panes", "5")
        AppSetting.first.update!(
          youtube_client_secret: "GOCSPX-super_secret_plaintext_42"
        )
        get settings_path
        expect(response.body).not_to include("GOCSPX-super_secret_plaintext_42")
      end
    end
  end

  describe "GET /settings search section" do
    let(:engine) { instance_double(Search::MeilisearchEngine) }

    before do
      allow(Search).to receive(:engine).and_return(engine)
      allow(engine).to receive(:per_index_stats).and_return({})
    end

    it "shows search engine status when healthy" do
      allow(engine).to receive(:healthy?).and_return(true)
      allow(engine).to receive(:index_stats).and_return({ "channels_test" => 10, "videos_test" => 50 })
      get settings_path
      expect(response.body).to include("Meilisearch")
      expect(response.body).to include("connected")
    end

    it "shows disconnected when unhealthy" do
      allow(engine).to receive(:healthy?).and_return(false)
      allow(engine).to receive(:index_stats).and_return({})
      get settings_path
      expect(response.body).to include("disconnected")
    end
  end

  describe "POST /settings/reindex" do
    it "enqueues ReindexAllJob and redirects" do
      post settings_reindex_path
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("reindex started")
    end

    it "enqueues the job" do
      expect { post settings_reindex_path }.to have_enqueued_job(ReindexAllJob)
    end
  end

  describe "GET /settings.json" do
    it "returns 200 with the public-safe settings JSON" do
      get settings_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "responds with the AppSettings shape pito-sh expects" do
      AppSetting.set("max_panes", "5")
      AppSetting.set("pane_title_length", "20")
      AppSetting.set("theme", "dark")
      get settings_path(format: :json)

      json = response.parsed_body
      expect(json.keys).to match_array(%w[max_panes pane_title_length theme])
      expect(json["max_panes"]).to eq(5)
      expect(json["pane_title_length"]).to eq(20)
      expect(json["theme"]).to eq("dark")
    end

    it "falls back to env defaults when AppSetting rows are absent" do
      get settings_path(format: :json)
      json = response.parsed_body
      expect(json["max_panes"]).to be_a(Integer).and(be > 0)
      expect(json["pane_title_length"]).to be_a(Integer).and(be > 0)
      expect(json["theme"]).to eq("auto")
    end

    it "does not leak the OAuth client secret or other private credentials" do
      AppSetting.set("youtube_client_secret", "super-secret")
      AppSetting.set("youtube_client_id", "client-id")
      AppSetting.set("youtube_redirect_uri", "http://example.test/cb")
      get settings_path(format: :json)
      body = response.body
      expect(body).not_to include("super-secret")
      expect(body).not_to include("client-id")
      expect(body).not_to include("http://example.test/cb")
    end

    it "is reachable without an authentication token" do
      # Pito's JSON API is open in this phase; the endpoint must answer 200
      # with no Authorization header set. (Mirrors pito-sh's current call.)
      get settings_path(format: :json)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /settings/theme" do
    it "sets theme to dark" do
      patch settings_theme_path, params: { theme: "dark" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("dark")
    end

    it "sets theme to light" do
      patch settings_theme_path, params: { theme: "light" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("light")
    end

    it "sets theme to auto" do
      patch settings_theme_path, params: { theme: "auto" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("auto")
    end

    it "rejects invalid theme values" do
      patch settings_theme_path, params: { theme: "neon" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
