require "rails_helper"

# Phase 8 — tenant drop. The Rack-app cross-tenant defense-in-depth
# check is gone. A token whose user is hard-deleted is still rejected
# as `invalid_token`.
RSpec.describe "Mcp::RackApp authentication", type: :request do
  let(:user) { User.first || create(:user) }

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

  describe "missing Authorization header" do
    it "returns 401 with {error: missing_token}" do
      post "/mcp", params: init_payload, headers: base_headers

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "missing_token")
    end
  end

  describe "unknown bearer" do
    it "returns 401 with {error: invalid_token}" do
      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer not-a-token")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "invalid_token")
    end
  end

  describe "revoked token" do
    it "returns 401 with {error: revoked_token}" do
      record, plaintext = ApiToken.generate!(
        user: user, name: "rv", scopes: [ Scopes::DEV_READ ]
      )
      record.revoke!

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "revoked_token")
    end
  end

  describe "expired token" do
    it "returns 401 with {error: expired_token}" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "ex", scopes: [ Scopes::DEV_READ ],
        expires_at: 1.minute.ago
      )

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "expired_token")
    end
  end

  describe "valid token" do
    it "returns 200 and proceeds with the MCP protocol" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "ok", scopes: Scopes::ALL.dup
      )

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["result"]["serverInfo"]["name"]).to eq("pito")
    end

    it "leaves Current.tenant nil after the request (it never gets set)" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "no-tenant", scopes: Scopes::ALL.dup
      )

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:ok)
      # `Current` is reset in the after-each hook, so `respond_to?` is
      # the right shape — `Current` no longer declares the attribute.
      expect(Current.respond_to?(:tenant)).to be(false)
    end
  end

  describe "scope enforcement on a tool" do
    it "rejects a dev:read-only token when calling a yt:read tool" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "narrow", scopes: [ Scopes::DEV_READ ]
      )

      headers = base_headers.merge("Authorization" => "Bearer #{plaintext}")
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

  describe "stray tenant_id in JSON-RPC params (flaw test)" do
    it "is ignored — the call still succeeds against the install scope" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "stray", scopes: Scopes::ALL.dup
      )
      payload = {
        jsonrpc: "2.0", id: 99, method: "initialize",
        params: {
          protocolVersion: "2025-03-26",
          capabilities: {},
          clientInfo: { name: "test", version: "1.0" },
          tenant_id: 999
        }
      }.to_json

      post "/mcp",
        params: payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "user hard-deleted between consent and bearer use (flaw test)" do
    it "returns 401 invalid_token" do
      # FKs from api_tokens → users prevent a direct hard-delete; the
      # only way the rack app reaches the `user.nil?` branch is if a
      # manual SQL delete drops the user row. Stub the association.
      _record, plaintext = ApiToken.generate!(
        user: user, name: "ghost", scopes: Scopes::ALL.dup
      )
      allow_any_instance_of(ApiToken).to receive(:user).and_return(nil)

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq("error" => "invalid_token")
    end
  end
end
