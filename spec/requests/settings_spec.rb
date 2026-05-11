require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:search_engine) { instance_double(Search::MeilisearchEngine, healthy?: true, index_stats: {}) }

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

    it "does NOT render the YouTube OAuth client credentials FORM (no inputs)" do
      get settings_path
      # The Phase 24 form fields are gone — assert by `name=`
      # attribute, the unambiguous form-input fingerprint.
      expect(response.body).not_to include('name="settings[youtube_client_id]"')
      expect(response.body).not_to include('name="settings[youtube_client_secret]"')
      expect(response.body).not_to include('name="settings[youtube_redirect_uri]"')
    end

    it "renders the YouTube credentials read-only status card" do
      get settings_path
      expect(response.body).to include("<h2>YouTube</h2>")
      # Each lookup row from `youtube_credentials_status` appears as
      # a labelled `<li>`. Status copy reflects the install state.
      expect(response.body).to include("public API key")
      expect(response.body).to include("OAuth client ID")
      expect(response.body).to include("OAuth client secret")
      expect(response.body).to include("OAuth redirect URI")
      # An empty test credentials store → every row is "not configured".
      expect(response.body).to include("not configured")
      # The card points the operator at the editing command.
      expect(response.body).to include("rails credentials:edit")
    end

    it "renders 'configured' on the YouTube card when a credential is present" do
      # Stub the YouTube lookup path only. Other credential paths
      # (sessions / auth, voyage, etc.) keep their normal behaviour
      # via `and_call_original`, so the rest of the request pipeline
      # is unaffected.
      creds = Rails.application.credentials
      allow(Rails.application).to receive(:credentials).and_return(creds)
      allow(creds).to receive(:dig).and_call_original
      allow(creds).to receive(:dig).with(:youtube, :public_api_key).and_return("pk_test")
      allow(creds).to receive(:dig).with(:youtube, :client_id).and_return(nil)
      allow(creds).to receive(:dig).with(:youtube, :client_secret).and_return(nil)
      allow(creds).to receive(:dig).with(:youtube, :redirect_uri).and_return(nil)

      get settings_path
      expect(response.body).to include("public API key")
      expect(response.body).to include("configured")
      # And confirm the other rows still say "not configured".
      expect(response.body).to include("OAuth client ID")
      expect(response.body).to include("not configured")
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

    it "renders three independent forms (workspaces, appearance, voyage)" do
      # Phase 24 — youtube_oauth section is gone with the Google card.
      get settings_path
      # Each per-section form carries a hidden `section` field.
      expect(response.body).to include('value="workspaces"')
      expect(response.body).to include('value="appearance"')
      expect(response.body).not_to include('value="youtube_oauth"')
      expect(response.body).to include('value="voyage"')
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
      # Phase 24 — three per-section forms remain (Google/YouTube cards
      # removed): appearance, workspaces, voyage.
      expect(response.body.scan("[update]").length).to be >= 3
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
      # Layout:
      #   row 1 — ui / ux | workspaces        (2 panes)
      #   row 2 — search | Voyage.ai          (2 panes)
      #   row 3 — YouTube (status, single)    (1 pane, right empty)
      #   row 4 — user | time zone            (2 panes; Phase 26 01a)
      #   row 5 — Slack | Discord             (2 panes; Phase 26 01b/01c)
      #   row 6 — OAuth+tokens | sessions     (2 panes; the OAuth /
      #     tokens cell still combines TWO sub-sections separated by
      #     a `<hr class="hairline">`, but counts as one pane).
      # NOTE: the inline `<%# Row N — … %>` labels in the ERB renumber
      # rows 3..5 to 4..6 for the layered (single-pane) rows; the test
      # only cares about the rendered structure, not the comment label.
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

    # 2026-05-10 — DOM order across the five paired rows. Row 1:
    # appearance, workspaces. Row 2 (new): YouTube credentials
    # status (single pane). Row 3: search, Voyage.ai. Row 4: user
    # (single). Row 5: OAuth applications + tokens (combined),
    # sessions. The YouTube card sits between general workspace
    # preferences and the search/Voyage integrations row — close to
    # its historic Phase 24 position.
    it "orders the panes appearance -> workspaces -> YouTube -> search -> Voyage -> user -> OAuth -> tokens -> sessions" do
      get settings_path
      idx_appearance = response.body.index('value="appearance"')
      idx_workspaces = response.body.index('value="workspaces"')
      idx_youtube    = response.body.index("<h2>YouTube</h2>")
      idx_search     = response.body.index("<h2>search</h2>")
      idx_voyage     = response.body.index('value="voyage"')
      idx_user       = response.body.index("<h2>user</h2>")
      idx_oauth_apps = response.body.index("<h2>OAuth applications</h2>")
      idx_tokens     = response.body.index("<h2>tokens</h2>")
      idx_sessions   = response.body.index("<h2>sessions</h2>")

      indices = [ idx_appearance, idx_workspaces,
                  idx_youtube, idx_search, idx_voyage, idx_user,
                  idx_oauth_apps, idx_tokens, idx_sessions ]
      expect(indices).to all(be_a(Integer))
      expect(indices).to eq(indices.sort)
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
  end

  describe "GET /settings search section" do
    let(:engine) { instance_double(Search::MeilisearchEngine) }

    before do
      allow(Search).to receive(:engine).and_return(engine)
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
