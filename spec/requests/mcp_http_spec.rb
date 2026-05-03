require "rails_helper"

RSpec.describe "MCP HTTP Transport", type: :request do
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
      "Accept" => "application/json"
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
      channel = create(:channel)

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
