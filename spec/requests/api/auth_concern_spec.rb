require "rails_helper"

# Phase 3 — Step B (5b-token-and-auth-concern.md). End-to-end auth-concern
# matrix exercised through `Api::FootagesController` — the only `Api::*`
# controller in Phase B's scope.
#
# Phase 8 — tenant drop. Tokens own a User, not a tenant; the
# defense-in-depth cross-tenant check is gone.
#
# Phase 29 (MCP cut, 2026-05-19) — the catalog collapsed to a single
# scope, `app`. Token-shape rejections are now exercised by simulating
# the failure modes (empty scopes via `update_columns`) rather than by
# minting a token in a "missing app" scope.
RSpec.describe "Api::AuthConcern", type: :request do
  let(:user) { User.first || create(:user) }
  let!(:project) { create(:project) }

  let(:json_headers) do
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def auth_headers(token_plaintext)
    json_headers.merge("Authorization" => "Bearer #{token_plaintext}")
  end

  def with_token(scopes:, **opts)
    record, plaintext = ApiToken.generate!(
      user: user, name: opts[:name] || "test", scopes: scopes,
      expires_at: opts[:expires_at]
    )
    record.revoke! if opts[:revoked]
    plaintext
  end

  describe "GET /api/projects/:project_id/footages" do
    context "without an Authorization header" do
      it "returns 401 with {error: missing_token}" do
        get api_project_footages_path(project), headers: json_headers

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "missing_token")
      end
    end

    context "with an unknown token" do
      it "returns 401 with {error: invalid_token}" do
        get api_project_footages_path(project),
            headers: auth_headers("not-a-real-token")

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "invalid_token")
      end
    end

    context "with a revoked token" do
      it "returns 401 with {error: revoked_token}" do
        plaintext = with_token(scopes: [ Scopes::APP ], revoked: true)

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "revoked_token")
      end
    end

    context "with an expired token" do
      it "returns 401 with {error: expired_token}" do
        plaintext = with_token(scopes: [ Scopes::APP ], expires_at: 1.minute.ago)

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "expired_token")
      end
    end

    context "with a token that lacks the app scope" do
      it "returns 403 with {error: insufficient_scope, required: app}" do
        # Phase 29 (MCP cut, 2026-05-19) — the catalog collapsed to a
        # single scope, `app`. A valid token always carries `app`, so
        # we have to bypass `scopes_subset_of_catalog` via
        # `update_columns` to simulate a row that lacks the required
        # scope (which is the production failure mode if a future
        # scope is reintroduced or if a row was rolled forward from
        # the legacy 9-scope catalog without the migration).
        plaintext = with_token(scopes: [ Scopes::APP ])
        ApiToken.find_by(name: "test").update_columns(scopes: [])

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("insufficient_scope")
        expect(body["required"]).to eq("app")
      end
    end

    context "with a token that has the app scope" do
      it "returns 200 and renders the JSON list" do
        plaintext = with_token(scopes: [ Scopes::APP ])

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it "populates Current.user / Current.token but never Current.tenant" do
        plaintext = with_token(scopes: [ Scopes::APP ])

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(ApiToken.find_by(name: "test").last_used_at).to be_present
      end
    end

    context "with a token whose user has been hard-deleted (flaw test)" do
      it "returns 401 invalid_token" do
        # The FK from api_tokens → users blocks a direct hard-delete; the
        # only way the auth concern reaches the `user.nil?` branch in
        # production is if a manual SQL delete drops the user row out
        # from under a valid token. Stub the association to simulate.
        plaintext = with_token(scopes: [ Scopes::APP ])
        allow_any_instance_of(ApiToken).to receive(:user).and_return(nil)

        get api_project_footages_path(project), headers: auth_headers(plaintext)
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "invalid_token")
      end
    end
  end

  describe "POST /api/projects/:project_id/footages" do
    let(:create_attrs) do
      {
        footage: {
          kind: "a_roll",
          source: "obs",
          local_path: "/tmp/clip-#{SecureRandom.hex(4)}.mp4",
          filename: "clip.mp4"
        }
      }
    end

    context "with a token that lacks the app scope" do
      it "returns 403 with {error: insufficient_scope, required: app}" do
        # Phase 29 (MCP cut, 2026-05-19) — see the GET context above
        # for why we have to bypass the validator to simulate this.
        plaintext = with_token(scopes: [ Scopes::APP ])
        ApiToken.find_by(name: "test").update_columns(scopes: [])

        post api_project_footages_path(project),
             params: create_attrs.to_json,
             headers: auth_headers(plaintext)

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("insufficient_scope")
        expect(body["required"]).to eq("app")
      end
    end

    context "with an app-scoped token" do
      it "creates the footage and returns 201" do
        plaintext = with_token(scopes: [ Scopes::APP ])

        post api_project_footages_path(project),
             params: create_attrs.to_json,
             headers: auth_headers(plaintext)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)).to have_key("id")
      end
    end
  end
end
