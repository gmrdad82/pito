require "rails_helper"

# Phase 8 — tenant drop. Tokens are install-wide.
RSpec.describe "Settings::Tokens", type: :request do
  let(:user) { User.first || create(:user) }

  before do
    Current.user = user
  end

  describe "GET /settings/tokens" do
    it "returns 200" do
      get settings_tokens_path
      expect(response).to have_http_status(:ok)
    end

    it "lists active tokens with name + scopes + preview" do
      token, = ApiToken.generate!(
        user: user,
        name: "alpha-token",
        scopes: [ Scopes::DEV ]
      )
      get settings_tokens_path
      expect(response.body).to include("alpha-token")
      expect(response.body).to include("dev")
      expect(response.body).to include("...#{token.last_token_preview}")
    end

    it "lists revoked tokens grayed and after active ones" do
      _active, = ApiToken.generate!(
        user: user,
        name: "still-good", scopes: [ Scopes::DEV ]
      )
      revoked, = ApiToken.generate!(
        user: user,
        name: "old-revoked", scopes: [ Scopes::DEV ]
      )
      revoked.revoke!

      get settings_tokens_path
      idx_active  = response.body.index("still-good")
      idx_revoked = response.body.index("old-revoked")
      expect(idx_active).not_to be_nil
      expect(idx_revoked).not_to be_nil
      expect(idx_active).to be < idx_revoked
      expect(response.body).to include("revoked")
    end

    it "shows a [new] link" do
      get settings_tokens_path
      expect(response.body).to include(">new<")
      expect(response.body).to include(new_settings_token_path)
    end
  end

  describe "GET /settings/tokens/new" do
    it "returns 200" do
      get new_settings_token_path
      expect(response).to have_http_status(:ok)
    end

    it "renders one checkbox per Scopes::DESCRIPTIONS entry" do
      get new_settings_token_path
      Scopes::DESCRIPTIONS.each do |scope, _|
        expect(response.body).to include(scope)
      end
    end

    # Phase 10 — the catalog has only two flat entries (`dev` + `app`);
    # there is no per-namespace grouping anymore.
    it "renders the dev and app scope checkboxes" do
      get new_settings_token_path
      expect(response.body).to include('value="dev"')
      expect(response.body).to include('value="app"')
    end

    it "shows the name input + expires_at date input" do
      get new_settings_token_path
      expect(response.body).to include('name="token[name]"')
      expect(response.body).to include('name="token[expires_at]"')
    end
  end

  describe "POST /settings/tokens" do
    it "mints a token and shows the plaintext exactly once" do
      post settings_tokens_path, params: {
        token: { name: "cli", scopes: [ Scopes::DEV, Scopes::APP ] }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<pre[^>]*class="[^"]*code-block[^"]*"[^>]*>\s*<code>[A-Za-z0-9_\-]{40,}<\/code>/)
      expect(response.body).to include("save this now")
    end

    it "creates the ApiToken with the chosen scopes" do
      expect {
        post settings_tokens_path, params: {
          token: { name: "cli2", scopes: [ Scopes::DEV, Scopes::APP ] }
        }
      }.to change { ApiToken.count }.by(1)
      token = ApiToken.order(:created_at).last
      expect(token.name).to eq("cli2")
      expect(token.scopes).to match_array([ Scopes::DEV, Scopes::APP ])
    end

    it "does not display the plaintext on subsequent index visits" do
      post settings_tokens_path, params: {
        token: { name: "ephemeral", scopes: [ Scopes::DEV ] }
      }
      response_body_1 = response.body
      plaintext_match = response_body_1.match(/<code>([A-Za-z0-9_\-]{40,})<\/code>/)
      expect(plaintext_match).not_to be_nil
      plaintext = plaintext_match[1]

      get settings_tokens_path
      expect(response.body).not_to include(plaintext)
    end

    it "rejects an empty scope list" do
      expect {
        post settings_tokens_path, params: {
          token: { name: "no-scopes", scopes: [] }
        }
      }.not_to change { ApiToken.count }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("at least one scope")
    end

    it "rejects an invalid scope entry" do
      expect {
        post settings_tokens_path, params: {
          token: { name: "bad", scopes: [ "bogus:scope" ] }
        }
      }.not_to change { ApiToken.count }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("invalid entries")
    end

    it "rejects a blank name" do
      expect {
        post settings_tokens_path, params: {
          token: { name: "", scopes: [ Scopes::DEV ] }
        }
      }.not_to change { ApiToken.count }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts an optional expires_at and stores it" do
      post settings_tokens_path, params: {
        token: { name: "expiring", scopes: [ Scopes::DEV ], expires_at: "2027-01-01" }
      }
      token = ApiToken.where(name: "expiring").last
      expect(token.expires_at).not_to be_nil
      expect(token.expires_at.to_date).to eq(Date.parse("2027-01-01"))
    end

    it "rejects a malformed expires_at" do
      expect {
        post settings_tokens_path, params: {
          token: { name: "bad-date", scopes: [ Scopes::DEV ], expires_at: "not-a-date" }
        }
      }.not_to change { ApiToken.count }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /settings/tokens/:id/revoke" do
    let(:token) do
      record, = ApiToken.generate!(
        user: user,
        name: "to-revoke", scopes: [ Scopes::DEV ]
      )
      record
    end

    it "renders the action confirmation screen" do
      get revoke_settings_token_path(token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("revoke token")
      expect(response.body).to include("to-revoke")
    end

    it "uses the action-screen footer (no JS confirm)" do
      get revoke_settings_token_path(token)
      expect(response.body).to include("action-screen-footer")
      expect(response.body).not_to include("data-turbo-confirm")
      expect(response.body).not_to match(/window\.confirm/i)
    end

    it "renders the revoke button styled as destructive" do
      get revoke_settings_token_path(token)
      expect(response.body).to include("[revoke]")
      expect(response.body).to include("btn-danger")
    end
  end

  describe "DELETE /settings/tokens/:id" do
    let!(:token) do
      record, = ApiToken.generate!(
        user: user,
        name: "to-revoke", scopes: [ Scopes::DEV ]
      )
      record
    end

    it "sets revoked_at without deleting the row" do
      expect {
        delete settings_token_path(token)
      }.not_to change { ApiToken.count }

      token.reload
      expect(token.revoked_at).to be_present
      expect(token).to be_revoked
    end

    it "redirects to the index with a flash" do
      delete settings_token_path(token)
      expect(response).to redirect_to(settings_tokens_path)
      follow_redirect!
      expect(response.body).to include("token revoked.")
    end

    it "no-ops idempotently when called on an already-revoked token" do
      token.revoke!
      original_revoked_at = token.revoked_at

      delete settings_token_path(token)
      expect(response).to redirect_to(settings_tokens_path)
      token.reload
      expect(token.revoked_at).to be_within(1.second).of(original_revoked_at)
    end
  end
end
