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

    it "shows the OAuth form fields" do
      get settings_path
      expect(response.body).to include("client ID")
      expect(response.body).to include("client secret")
      expect(response.body).to include("redirect URI")
    end

    it "displays existing values" do
      AppSetting.set("youtube_client_id", "test-client-id")
      get settings_path
      expect(response.body).to include("test-client-id")
    end

    it "shows the theme selector" do
      get settings_path
      expect(response.body).to include("appearance")
      expect(response.body).to include("light")
      expect(response.body).to include("dark")
      expect(response.body).to include("auto (system)")
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

    it "renders four independent forms (workspaces, appearance, oauth, voyage)" do
      get settings_path
      # Each per-section form carries a hidden `section` field.
      expect(response.body).to include('value="workspaces"')
      expect(response.body).to include('value="appearance"')
      expect(response.body).to include('value="youtube_oauth"')
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
      # All four per-section forms render the same updated button text.
      expect(response.body.scan("[update]").length).to be >= 4
      # The pre-revamp `[save]` text is gone everywhere on the page.
      expect(response.body).not_to include("[save]")
    end

    it "renders settings as five .pane-row groups holding nine total panes" do
      # Phase 12 polish (2026-05-10) — the page is regrouped into five
      # paired rows: row 1 appearance | workspaces, row 2 Google |
      # YouTube, row 3 search | Voyage.ai, row 4 user (single pane;
      # right side intentionally empty), row 5 OAuth-applications +
      # tokens combined | sessions. The OAuth-applications and tokens
      # surfaces share one pane separated by a `<hr class="hairline">`
      # so two related token-issuance sections live next to each
      # other, dropping the total pane count from ten to nine. The
      # global `:nth-child` zebra rule continues to handle A/B
      # alternation per row — no inline backgrounds in markup.
      get settings_path
      expect(response.body.scan(/class="pane-row"/).length).to eq(5)
      panes = response.body.scan(/class="pane(?:\s[^"]*)?"/).size
      expect(panes).to eq(9)
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

    # Phase 12 polish (2026-05-10) — DOM order across the five
    # paired rows. Row 1: appearance, workspaces. Row 2: Google,
    # YouTube. Row 3: search, Voyage.ai. Row 4: user. Row 5: OAuth
    # applications + tokens (combined), sessions.
    it "orders the panes appearance -> workspaces -> Google -> YouTube -> search -> Voyage -> user -> OAuth -> tokens -> sessions" do
      get settings_path
      idx_appearance = response.body.index('value="appearance"')
      idx_workspaces = response.body.index('value="workspaces"')
      idx_google     = response.body.index("<h2>Google</h2>")
      idx_oauth      = response.body.index('value="youtube_oauth"')
      idx_search     = response.body.index("<h2>search</h2>")
      idx_voyage     = response.body.index('value="voyage"')
      idx_user       = response.body.index("<h2>user</h2>")
      idx_oauth_apps = response.body.index("<h2>OAuth applications</h2>")
      idx_tokens     = response.body.index("<h2>tokens</h2>")
      idx_sessions   = response.body.index("<h2>sessions</h2>")

      indices = [ idx_appearance, idx_workspaces, idx_google, idx_oauth,
                  idx_search, idx_voyage, idx_user, idx_oauth_apps,
                  idx_tokens, idx_sessions ]
      expect(indices).to all(be_a(Integer))
      expect(indices).to eq(indices.sort)
    end

    it "renders the tokens pane with a link to /settings/tokens" do
      get settings_path
      expect(response.body).to include("<h2>tokens</h2>")
      expect(response.body).to include(settings_tokens_path)
    end

    # Phase 12 polish (2026-05-10) — brand casing exceptions to the
    # site-wide lowercase tone. Pin them in the markup so future
    # regressions don't quietly downcase a brand name.
    it "uses brand casing for Google, YouTube, Voyage.ai, and OAuth" do
      get settings_path
      expect(response.body).to include("<h2>Google</h2>")
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

    # Phase 12 polish — the YouTube client secret field is masked the
    # same way Voyage.ai's API key field is. The stored secret value
    # MUST NOT round-trip into the form's `value=""`. The rendered
    # placeholder reflects the configured / not-configured state.
    it "does not echo the YouTube client secret into the form value" do
      AppSetting.set("youtube_client_secret", "super-secret-shhh")
      get settings_path
      # No <input> for the secret carries a value="..." with the plaintext.
      expect(response.body).not_to include("super-secret-shhh")
      # The placeholder reflects the configured state.
      expect(response.body).to include("secret configured")
    end

    it "shows a 'no secret configured' placeholder when the secret is blank" do
      get settings_path
      expect(response.body).to include("no secret configured")
    end

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

  # 2026-05-10 polish — Google pane on the Settings index. The pane
  # summarises every YoutubeConnection owned by Current.user plus an
  # aggregated channel count (with up to five known titles) across
  # those connections. Brand-account emails (`*@pages.plusgoogle.com`)
  # are truncated to their local part via `YoutubeHelper#format_connection_email`.
  describe "GET /settings — Google pane channels summary" do
    let(:user) { User.first }
    let(:valid_url) do
      ->(i) {
        suffix = ("a".."z").to_a[i].to_s * 22
        "https://www.youtube.com/channel/UC#{suffix[0, 22]}"
      }
    end

    it "renders 'connected: no' with no summary line when no YoutubeConnection exists" do
      get settings_path
      expect(response.body).to include("connected: no")
      expect(response.body).not_to include("channels:")
      expect(response.body).not_to include("no channels linked yet")
    end

    it "renders the empty-state phrasing when connected but no channels exist yet" do
      create(:youtube_connection, user: user, email: "u@gmail.com")
      get settings_path
      expect(response.body).to include("connected: yes")
      expect(response.body).to include("no channels linked yet")
    end

    it "renders '1 channel' (singular, no titles) when only one un-synced channel exists" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to match(/1 channel(?!s)/)
      expect(response.body).not_to include("1 channel:")
    end

    it "renders 'N channels' (no titles) when channels have nil titles" do
      connection = create(:youtube_connection, user: user)
      3.times { |i|
        Channel.create!(channel_url: valid_url.call(i),
                        youtube_connection_id: connection.id)
      }
      get settings_path
      expect(response.body).to match(/3 channels(?!:)/)
    end

    it "renders '1 channel: Title' when one channel has a title" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      title: "Catalin Ilinca",
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to include("1 channel: Catalin Ilinca")
    end

    it "renders 'N channels: A, B, C' with comma-separated titles" do
      connection = create(:youtube_connection, user: user)
      [ "Alpha", "Bravo", "Charlie" ].each_with_index do |t, i|
        Channel.create!(channel_url: valid_url.call(i),
                        title: t,
                        youtube_connection_id: connection.id)
      end
      get settings_path
      expect(response.body).to include("3 channels: Alpha, Bravo, Charlie")
    end

    it "truncates to first 5 titles and appends '…and N more' beyond that" do
      connection = create(:youtube_connection, user: user)
      titles = %w[Alpha Bravo Charlie Delta Echo Foxtrot Golf]
      titles.each_with_index do |t, i|
        Channel.create!(channel_url: valid_url.call(i),
                        title: t,
                        youtube_connection_id: connection.id)
      end
      get settings_path
      expect(response.body).to include("7 channels: Alpha, Bravo, Charlie, Delta, Echo, …and 2 more")
      expect(response.body).not_to include("Foxtrot")
      expect(response.body).not_to include("Golf")
    end

    it "strips the @pages.plusgoogle.com domain from a brand-account email" do
      create(:youtube_connection, user: user,
                                  email: "mushroom-poise-2296566909359968898@pages.plusgoogle.com")
      get settings_path
      expect(response.body).to include("mushroom-poise-2296566909359968898")
      expect(response.body).not_to include("@pages.plusgoogle.com")
    end

    it "leaves a gmail.com email untouched" do
      create(:youtube_connection, user: user, email: "alice@gmail.com")
      get settings_path
      expect(response.body).to include("alice@gmail.com")
    end

    it "renders every connection email on its own line when multiple connections exist" do
      create(:youtube_connection, user: user,
                                  email: "first@gmail.com",
                                  last_authorized_at: 2.hours.ago)
      create(:youtube_connection, user: user,
                                  email: "second@pages.plusgoogle.com",
                                  last_authorized_at: 1.hour.ago)
      get settings_path
      expect(response.body).to include("first@gmail.com")
      expect(response.body).to include("second")
      # The brand-account-style email is truncated (no `@pages.plusgoogle.com`)
      expect(response.body).not_to include("second@pages.plusgoogle.com")
    end

    it "aggregates channel counts across ALL connections owned by the user" do
      conn_a = create(:youtube_connection, user: user)
      conn_b = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0), title: "From A",
                      youtube_connection_id: conn_a.id)
      Channel.create!(channel_url: valid_url.call(1), title: "From B",
                      youtube_connection_id: conn_b.id)
      get settings_path
      expect(response.body).to include("2 channels:")
      expect(response.body).to include("From A")
      expect(response.body).to include("From B")
    end

    it "appends a '+N more' indicator to last-authorized when multiple connections exist" do
      create(:youtube_connection, user: user,
                                  email: "first@gmail.com",
                                  last_authorized_at: 3.hours.ago)
      create(:youtube_connection, user: user,
                                  email: "second@gmail.com",
                                  last_authorized_at: 1.hour.ago)
      create(:youtube_connection, user: user,
                                  email: "third@gmail.com",
                                  last_authorized_at: 30.minutes.ago)
      get settings_path
      expect(response.body).to match(/last authorized .+ \(\+2 more\)/)
    end

    it "does NOT append a '+N more' indicator when only one connection exists" do
      create(:youtube_connection, user: user, email: "solo@gmail.com")
      get settings_path
      expect(response.body).not_to include("+0 more")
      expect(response.body).not_to include("more)")
    end
  end

  describe "PATCH /settings" do
    it "saves new settings and redirects" do
      patch settings_path, params: {
        settings: {
          youtube_client_id: "my-client-id",
          youtube_client_secret: "my-secret",
          youtube_redirect_uri: "http://localhost:3000/oauth/callback"
        }
      }
      expect(response).to redirect_to(settings_path)
      expect(AppSetting.get("youtube_client_id")).to eq("my-client-id")
      expect(AppSetting.get("youtube_client_secret")).to eq("my-secret")
      expect(AppSetting.get("youtube_redirect_uri")).to eq("http://localhost:3000/oauth/callback")
    end

    it "updates existing settings" do
      AppSetting.set("youtube_client_id", "old-id")
      patch settings_path, params: {
        settings: { youtube_client_id: "new-id", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      expect(AppSetting.get("youtube_client_id")).to eq("new-id")
    end

    it "does not blank out existing settings when value is empty" do
      AppSetting.set("youtube_client_secret", "keep-this")
      patch settings_path, params: {
        settings: { youtube_client_id: "new-id", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      expect(AppSetting.get("youtube_client_secret")).to eq("keep-this")
    end

    it "shows flash notice after save" do
      patch settings_path, params: {
        settings: { youtube_client_id: "x", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      follow_redirect!
      expect(response.body).to include("settings saved.")
    end
  end

  # Phase B refinement (2026-05-04) — per-fieldset submits. Each fieldset has
  # its own form with a hidden `section` field. PATCH-ing a single section
  # MUST NOT touch fields that belong to other sections.
  describe "PATCH /settings (per-section submits)" do
    it "workspaces section saves only general keys, leaves theme/oauth alone" do
      AppSetting.set("theme", "dark")
      AppSetting.set("youtube_client_id", "keep-id")
      patch settings_path, params: {
        section: "workspaces",
        settings: { pane_title_length: "20", max_panes: "7" }
      }
      expect(AppSetting.get("pane_title_length")).to eq("20")
      expect(AppSetting.get("max_panes")).to eq("7")
      expect(AppSetting.get("theme")).to eq("dark")
      expect(AppSetting.get("youtube_client_id")).to eq("keep-id")
    end

    it "appearance section saves only the theme, leaves general/oauth alone" do
      AppSetting.set("max_panes", "9")
      AppSetting.set("youtube_client_id", "keep-id")
      patch settings_path, params: {
        section: "appearance",
        settings: { theme: "light" }
      }
      expect(AppSetting.get("theme")).to eq("light")
      expect(AppSetting.get("max_panes")).to eq("9")
      expect(AppSetting.get("youtube_client_id")).to eq("keep-id")
    end

    it "youtube_oauth section saves only oauth keys, leaves general/theme alone" do
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
      expect(AppSetting.get("youtube_client_id")).to eq("new-id")
      expect(AppSetting.get("youtube_client_secret")).to eq("new-secret")
      expect(AppSetting.get("youtube_redirect_uri")).to eq("http://example.test/cb")
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
