require "rails_helper"

# Phase 7.5 — Closes Phase 6B deviation #2: Doorkeeper-issued OAuth
# access tokens authenticate at `/mcp` through the same dispatch as
# Phase 5 ApiToken bearers. Coverage matrix:
#
#   - valid OAuth bearer → 200, MCP protocol proceeds
#   - revoked OAuth bearer → 401 `revoked_token`
#   - expired OAuth bearer → 401 `expired_token`
#   - OAuth bearer with insufficient scope → tool-call error envelope
#   - 401 carries the WWW-Authenticate challenge with as_uri/resource_uri
#
# Phase 8 — tenant drop. The cross-tenant defense-in-depth check is
# gone (single install). A token whose resource owner is hard-deleted
# is still rejected as `invalid_token`.
RSpec.describe "Mcp::RackApp OAuth bearer acceptance", type: :request do
  let(:user) { User.first || create(:user) }
  let!(:application) do
    create(
      :oauth_application,
      name: "claude-mcp-spec",
      scopes: Scopes::ALL.join(" ")
    )
  end

  let(:init_payload) do
    {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test", version: "1.0" }
      }
    }.to_json
  end

  let(:base_headers) do
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def mint_oauth_token(scopes:, expires_in: 2.hours.to_i, revoked_at: nil)
    token = OauthAccessToken.create!(
      application: application,
      resource_owner_id: user.id,
      scopes: Array(scopes).join(" "),
      expires_in: expires_in
    )
    token.update_column(:revoked_at, revoked_at) if revoked_at
    token
  end

  describe "valid OAuth access token" do
    it "authenticates and proceeds with the MCP protocol" do
      token = mint_oauth_token(scopes: Scopes::ALL)

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{token.token}")

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["result"]["serverInfo"]["name"]).to eq("pito")
    end

    it "pins Current.user from the OAuth token's owner" do
      token = mint_oauth_token(scopes: [ Scopes::YT_READ ])
      headers = base_headers.merge("Authorization" => "Bearer #{token.token}")

      post "/mcp", params: init_payload, headers: headers
      session_id = response.headers["Mcp-Session-Id"]

      tools_call = {
        jsonrpc: "2.0", id: 2, method: "tools/call",
        params: { name: "list_channels", arguments: {} }
      }.to_json
      post "/mcp",
        params: tools_call,
        headers: headers.merge("Mcp-Session-Id" => session_id)

      data = JSON.parse(response.body)
      expect(data["result"]["isError"]).to be_falsey
    end
  end

  describe "revoked OAuth access token" do
    it "returns 401 with {error: revoked_token}" do
      token = mint_oauth_token(scopes: Scopes::ALL, revoked_at: 1.minute.ago)

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{token.token}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "revoked_token")
    end
  end

  describe "expired OAuth access token" do
    it "returns 401 with {error: expired_token}" do
      token = mint_oauth_token(scopes: Scopes::ALL)
      token.update_column(:created_at, 4.hours.ago)

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{token.token}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "expired_token")
    end
  end

  describe "scope enforcement on a tool" do
    it "rejects a dev:read-only OAuth token when calling a yt:read tool" do
      token = mint_oauth_token(scopes: [ Scopes::DEV_READ ])
      headers = base_headers.merge("Authorization" => "Bearer #{token.token}")

      post "/mcp", params: init_payload, headers: headers
      session_id = response.headers["Mcp-Session-Id"]

      tools_call = {
        jsonrpc: "2.0", id: 2, method: "tools/call",
        params: { name: "list_channels", arguments: {} }
      }.to_json
      post "/mcp",
        params: tools_call,
        headers: headers.merge("Mcp-Session-Id" => session_id)

      data = JSON.parse(response.body)
      content_text = data["result"]["content"].first["text"]
      payload = JSON.parse(content_text)

      expect(data["result"]["isError"]).to be true
      expect(payload["error"]).to eq("insufficient_scope")
      expect(payload["required"]).to eq("yt:read")
    end
  end

  describe "WWW-Authenticate header on 401" do
    it "advertises the OAuth metadata locations on missing-bearer 401" do
      post "/mcp", params: init_payload, headers: base_headers

      expect(response).to have_http_status(:unauthorized)
      challenge = response.headers["WWW-Authenticate"]
      expect(challenge).to include("Bearer")
      expect(challenge).to include('realm="pito"')
      expect(challenge).to include("as_uri=\"https://app.pitomd.com/.well-known/oauth-authorization-server\"")
      expect(challenge).to include("resource_uri=\"https://mcp.pitomd.com/.well-known/oauth-protected-resource\"")
    end

    it "also advertises the metadata on revoked-token 401" do
      token = mint_oauth_token(scopes: Scopes::ALL, revoked_at: 1.minute.ago)
      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{token.token}")

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include("Bearer realm=\"pito\"")
    end
  end

  describe "Phase 8 — user hard-delete defense-in-depth" do
    it "refuses an OAuth token whose resource owner row is missing" do
      # OAuth access tokens hold `resource_owner_id` as a plain bigint
      # (no FK on the column), so we can simulate the missing-user
      # state by minting the token with a dangling id.
      token = OauthAccessToken.create!(
        application: application,
        resource_owner_id: 99_999_999,
        scopes: Scopes::ALL.join(" "),
        expires_in: 2.hours.to_i
      )

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{token.token}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "invalid_token")
    end
  end
end
