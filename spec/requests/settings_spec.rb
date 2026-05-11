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

  # 2026-05-10 — Google pane on the Settings index. The pane renders
  # a `channels:` list (one label per row) aggregated across every
  # YoutubeConnection owned by Current.user.
  #
  # 2026-05-10 (image #66) — the channels block dropped the count
  # prefix ("103 channels:") in favour of a muted `channels:` header
  # and one label per row. Labels resolve to the channel's `title`
  # once the sync job populates it, falling back to the UC-id slug
  # extracted from `channel_url`.
  #
  # 2026-05-10 copy fix — the card no longer renders per-connection
  # email lines or the `last authorized YYYY-MM-DD HH:MM UTC (+N more)`
  # paragraph. Negative guards live in the nested
  # "Google card copy fix" describe block below.
  describe "GET /settings — Google pane channels list" do
    let(:user) { User.first }
    let(:valid_url) do
      ->(i) {
        suffix = ("a".."z").to_a[i].to_s * 22
        "https://www.youtube.com/channel/UC#{suffix[0, 22]}"
      }
    end

    it "renders 'connected: no' with no channels block when no YoutubeConnection exists" do
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

    it "renders a muted 'channels:' header (no count prefix) when channels exist" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      title: "Catalin Ilinca",
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to include("channels:")
      # The pre-refactor "N channels:" count prefix is gone.
      expect(response.body).not_to match(/\d+ channels?:/)
    end

    it "renders each channel title on its own line inside a list" do
      connection = create(:youtube_connection, user: user)
      [ "Alpha", "Bravo", "Charlie" ].each_with_index do |t, i|
        Channel.create!(channel_url: valid_url.call(i),
                        title: t,
                        youtube_connection_id: connection.id)
      end
      get settings_path
      # Each title lives in its own <li>.
      expect(response.body).to include("<li>Alpha</li>")
      expect(response.body).to include("<li>Bravo</li>")
      expect(response.body).to include("<li>Charlie</li>")
      # And no inline comma-separated form anywhere on the page.
      expect(response.body).not_to include("Alpha, Bravo, Charlie")
    end

    it "falls back to the UC-id slug when a channel has no title yet" do
      connection = create(:youtube_connection, user: user)
      uc_slug = "UC#{('a' * 22)[0, 22]}"
      Channel.create!(channel_url: "https://www.youtube.com/channel/#{uc_slug}",
                      title: nil,
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to include("<li>#{uc_slug}</li>")
    end

    it "prefers title over UC-id when both could resolve" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      title: "Real Title",
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to include("<li>Real Title</li>")
      expect(response.body).not_to include("<li>UC")
    end

    it "treats a whitespace-only title as blank and falls back to UC-id" do
      connection = create(:youtube_connection, user: user)
      uc_slug = "UC#{('b' * 22)[0, 22]}"
      Channel.create!(channel_url: "https://www.youtube.com/channel/#{uc_slug}",
                      title: "   ",
                      youtube_connection_id: connection.id)
      get settings_path
      expect(response.body).to include("<li>#{uc_slug}</li>")
    end

    it "caps the list at 5 labels and appends '…and N more' beyond that" do
      connection = create(:youtube_connection, user: user)
      titles = %w[Alpha Bravo Charlie Delta Echo Foxtrot Golf]
      titles.each_with_index do |t, i|
        Channel.create!(channel_url: valid_url.call(i),
                        title: t,
                        youtube_connection_id: connection.id)
      end
      get settings_path
      # The first 5 (titled rows ordered by title asc) appear; Foxtrot and
      # Golf are summarized by the "+N more" footer line.
      expect(response.body).to include("<li>Alpha</li>")
      expect(response.body).to include("<li>Bravo</li>")
      expect(response.body).to include("<li>Charlie</li>")
      expect(response.body).to include("<li>Delta</li>")
      expect(response.body).to include("<li>Echo</li>")
      expect(response.body).not_to include("<li>Foxtrot</li>")
      expect(response.body).not_to include("<li>Golf</li>")
      expect(response.body).to include("…and 2 more")
    end

    it "aggregates channel labels across ALL connections owned by the user" do
      conn_a = create(:youtube_connection, user: user)
      conn_b = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0), title: "From A",
                      youtube_connection_id: conn_a.id)
      Channel.create!(channel_url: valid_url.call(1), title: "From B",
                      youtube_connection_id: conn_b.id)
      get settings_path
      expect(response.body).to include("channels:")
      expect(response.body).to include("<li>From A</li>")
      expect(response.body).to include("<li>From B</li>")
    end

    it "orders titled channels before un-titled (UC-id fallback) channels" do
      connection = create(:youtube_connection, user: user)
      Channel.create!(channel_url: valid_url.call(0),
                      title: nil,
                      youtube_connection_id: connection.id)
      Channel.create!(channel_url: valid_url.call(1),
                      title: "Zeta",
                      youtube_connection_id: connection.id)
      get settings_path
      zeta_idx = response.body.index("<li>Zeta</li>")
      uc_idx = response.body.index("<li>UC")
      expect(zeta_idx).not_to be_nil
      expect(uc_idx).not_to be_nil
      expect(zeta_idx).to be < uc_idx
    end

    it "keeps the connect-a-Google-account hint paragraph in place" do
      get settings_path
      expect(response.body).to include(
        "connect a Google account to fetch YouTube channel and analytics data."
      )
    end

    # 2026-05-10 copy fix — the Google card dropped the per-connection
    # email lines and the `last authorized YYYY-MM-DD HH:MM:SS UTC
    # (+N more)` indicator. The card now reads: heading + "connected:
    # yes/no" + channels block + hint + [manage]. Negative guards pin
    # the contract so future work doesn't quietly reintroduce either
    # block.
    describe "Google card copy fix (no emails, no last-authorized line)" do
      it "does not render any @-bearing email line when one connection exists" do
        create(:youtube_connection, user: user, email: "alice@gmail.com")
        get settings_path
        expect(response.body).not_to include("@gmail.com")
      end

      it "does not render brand-account email fragments either" do
        create(:youtube_connection, user: user,
                                    email: "mushroom-poise-2296566909359968898@pages.plusgoogle.com")
        get settings_path
        expect(response.body).not_to include("mushroom-poise-2296566909359968898")
        expect(response.body).not_to include("@pages.plusgoogle.com")
      end

      it "does not render any 'last authorized' line" do
        create(:youtube_connection, user: user,
                                    email: "first@gmail.com",
                                    last_authorized_at: 2.hours.ago)
        create(:youtube_connection, user: user,
                                    email: "second@gmail.com",
                                    last_authorized_at: 1.hour.ago)
        get settings_path
        expect(response.body).not_to match(/last authorized/i)
        expect(response.body).not_to include("+1 more")
        expect(response.body).not_to include("more)")
      end
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
