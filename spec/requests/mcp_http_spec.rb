require "rails_helper"

RSpec.describe "MCP HTTP Transport", type: :request do
  let(:tenant) { Tenant.first || create(:tenant) }
  let(:user)   { User.first  || create(:user, tenant: tenant) }

  # Mint a token with both yt:* and dev:* scopes so all tools can be
  # exercised. Tests that need to assert per-scope rejection mint a
  # narrower token.
  let(:auth_pair) do
    ApiToken.generate!(
      tenant: tenant, user: user, name: "mcp-http-spec",
      scopes: [
        Scopes::DEV_READ, Scopes::DEV_WRITE,
        Scopes::YT_READ, Scopes::YT_WRITE, Scopes::YT_DESTRUCTIVE
      ]
    )
  end
  let(:plaintext) { auth_pair.last }

  let(:init_payload) do
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test", version: "1.0" }
      }
    }.to_json
  end

  let(:tools_list_payload) do
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: {}
    }.to_json
  end

  let(:headers) do
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Authorization" => "Bearer #{plaintext}"
    }
  end

  describe "MCP protocol" do
    it "returns server info on initialize" do
      post "/mcp", params: init_payload, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["result"]["protocolVersion"]).to eq("2025-03-26")
      expect(data["result"]["serverInfo"]["name"]).to eq("pito")
    end

    it "returns tools list" do
      post "/mcp", params: init_payload, headers: headers
      session_id = response.headers["Mcp-Session-Id"]

      post "/mcp",
        params: tools_list_payload,
        headers: headers.merge("Mcp-Session-Id" => session_id)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      tool_names = data["result"]["tools"].map { |t| t["name"] }
      expect(tool_names).to include("list_channels", "get_dashboard", "search")
    end

    it "calls a tool successfully" do
      # The factory's default-scope-driven uniqueness validation needs a
      # tenant context. Request specs don't pre-populate Current, so set
      # it for the factory call only — the auth concern repopulates from
      # the resolved token on the actual request.
      Current.tenant = tenant
      channel = create(:channel, tenant: tenant)
      Current.reset

      post "/mcp", params: init_payload, headers: headers
      session_id = response.headers["Mcp-Session-Id"]

      call_payload = {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: { name: "list_channels", arguments: {} }
      }.to_json

      post "/mcp",
        params: call_payload,
        headers: headers.merge("Mcp-Session-Id" => session_id)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      content = data["result"]["content"].first["text"]
      expect(content).to include(channel.channel_url)
    end
  end
end
