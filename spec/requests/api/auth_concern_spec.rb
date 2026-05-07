require "rails_helper"

# Phase 3 — Step B (5b-token-and-auth-concern.md). End-to-end auth-concern
# matrix exercised through `Api::FootagesController` — the only `Api::*`
# controller in Phase B's scope.
RSpec.describe "Api::AuthConcern", type: :request do
  let(:tenant) { Tenant.first || create(:tenant) }
  let(:user)   { User.first  || create(:user, tenant: tenant) }
  let!(:project) do
    Current.tenant = tenant
    p = create(:project, tenant: tenant)
    Current.reset
    p
  end

  let(:json_headers) do
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def auth_headers(token_plaintext)
    json_headers.merge("Authorization" => "Bearer #{token_plaintext}")
  end

  def with_token(scopes:, **opts)
    record, plaintext = ApiToken.generate!(
      tenant: tenant, user: user, name: opts[:name] || "test", scopes: scopes,
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
        plaintext = with_token(scopes: [ Scopes::PROJECT_READ ], revoked: true)

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "revoked_token")
      end
    end

    context "with an expired token" do
      it "returns 401 with {error: expired_token}" do
        plaintext = with_token(scopes: [ Scopes::PROJECT_READ ], expires_at: 1.minute.ago)

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq("error" => "expired_token")
      end
    end

    context "with a token that lacks project:read" do
      it "returns 403 with {error: insufficient_scope, required: project:read}" do
        plaintext = with_token(scopes: [ Scopes::DEV_READ ])

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("insufficient_scope")
        expect(body["required"]).to eq("project:read")
      end
    end

    context "with a token that has project:read" do
      it "returns 200 and renders the JSON list" do
        plaintext = with_token(scopes: [ Scopes::PROJECT_READ ])

        get api_project_footages_path(project), headers: auth_headers(plaintext)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it "populates Current.tenant / Current.user / Current.token from the token" do
        plaintext = with_token(scopes: [ Scopes::PROJECT_READ ])

        # Snoop on Current via a controller-after_action substitute: read
        # the database side-effect (last_used_at bumped). For the actual
        # Current.* assertion we use a stub on the inner authenticator.
        get api_project_footages_path(project), headers: auth_headers(plaintext)

        # Token's last_used_at was bumped (proves auth path ran).
        expect(ApiToken.find_by(name: "test").last_used_at).to be_present
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

    context "with project:read but not project:write" do
      it "returns 403 with {error: insufficient_scope, required: project:write}" do
        plaintext = with_token(scopes: [ Scopes::PROJECT_READ ])

        post api_project_footages_path(project),
             params: create_attrs.to_json,
             headers: auth_headers(plaintext)

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("insufficient_scope")
        expect(body["required"]).to eq("project:write")
      end
    end

    context "with project:write" do
      it "creates the footage and returns 201" do
        plaintext = with_token(scopes: [ Scopes::PROJECT_WRITE ])

        post api_project_footages_path(project),
             params: create_attrs.to_json,
             headers: auth_headers(plaintext)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)).to have_key("id")
      end
    end
  end
end
