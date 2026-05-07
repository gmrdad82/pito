require "rails_helper"

RSpec.describe "Mcp::RackApp authentication", type: :request do
  let(:tenant) { Tenant.first || create(:tenant) }
  let(:user)   { User.first  || create(:user, tenant: tenant) }

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
        tenant: tenant, user: user, name: "rv", scopes: [ Scopes::DEV_READ ]
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
        tenant: tenant, user: user, name: "ex", scopes: [ Scopes::DEV_READ ],
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
        tenant: tenant, user: user, name: "ok", scopes: Scopes::ALL.dup
      )

      post "/mcp",
        params: init_payload,
        headers: base_headers.merge("Authorization" => "Bearer #{plaintext}")

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["result"]["serverInfo"]["name"]).to eq("pito")
    end
  end

  describe "scope enforcement on a tool" do
    it "rejects a dev:read-only token when calling a yt:read tool" do
      _record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "narrow", scopes: [ Scopes::DEV_READ ]
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
end
