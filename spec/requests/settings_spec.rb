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

    it "shows the Voyage AI fieldset with the current flag value" do
      AppSetting.set("max_panes", "5")
      AppSetting.first.update!(
        voyage_api_key: "vk_test",
        voyage_index_project_notes: true
      )
      get settings_path
      expect(response.body).to include("Voyage AI")
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
      # The pre-revamp `[ save ]` text is gone everywhere on the page.
      expect(response.body).not_to include("[ save ]")
    end

    it "renders each section cell on the pane background" do
      get settings_path
      # The cells reuse the existing `--color-pane-bg` token; no new CSS.
      expect(response.body).to include("var(--color-pane-bg)")
    end

    it "renders rows 1 and 2 as two-column grids" do
      get settings_path
      # Two grids = two 2-col rows (appearance|workspaces, oauth|voyage).
      grid_hits = response.body.scan("grid-template-columns: 1fr 1fr").length
      expect(grid_hits).to eq(2)
    end

    # Row order: row 1 (appearance, workspaces), row 2 (oauth, voyage),
    # row 3 (search). Asserting via DOM order keeps the structure intact.
    it "orders the sections appearance -> workspaces -> oauth -> voyage -> search" do
      get settings_path
      idx_appearance = response.body.index('value="appearance"')
      idx_workspaces = response.body.index('value="workspaces"')
      idx_oauth      = response.body.index('value="youtube_oauth"')
      idx_voyage     = response.body.index('value="voyage"')
      idx_search     = response.body.index("<h2>search</h2>")

      expect([ idx_appearance, idx_workspaces, idx_oauth, idx_voyage, idx_search ])
        .to all(be_a(Integer))
      expect(idx_appearance).to be < idx_workspaces
      expect(idx_workspaces).to be < idx_oauth
      expect(idx_oauth).to be < idx_voyage
      expect(idx_voyage).to be < idx_search
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
      expect(response.body).to include("meilisearch")
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
