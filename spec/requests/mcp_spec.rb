# frozen_string_literal: true

require "rails_helper"

# Request spec for the MCP JSON-RPC endpoint (POST /mcp). The Bearer gate is
# stubbed at Pito::Mcp::Auth (its real oauth_tokens lookup is P4); this pins the
# JSON-RPC framing, the method dispatch, and the 401 shape.
RSpec.describe "POST /mcp", type: :request do
  let(:headers) { { "Authorization" => "Bearer valid-token", "Content-Type" => "application/json" } }

  def rpc(body, hdrs: headers)
    post "/mcp", params: body.is_a?(String) ? body : body.to_json, headers: hdrs
    response.parsed_body
  end

  describe "the Bearer gate" do
    it "401s with a WWW-Authenticate resource_metadata pointer when no token is present" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
                   headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to match(%r{Bearer resource_metadata=".*/\.well-known/oauth-protected-resource"})
    end

    it "401s when the token does not resolve" do
      allow(Pito::Mcp::Auth).to receive(:authenticate).and_return(nil)
      rpc({ jsonrpc: "2.0", id: 1, method: "ping" })
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a REAL issued OAuth access token end-to-end (no stub)" do
      client = OauthClient.register(name: "c", redirect_uris: [ "https://c/cb" ])
      access, = OauthToken.issue(client_id: client.client_id)

      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
                   headers: { "Authorization" => "Bearer #{access}", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["result"]).to eq({})
    end

    it "401s a revoked real token" do
      client = OauthClient.register(name: "c", redirect_uris: [ "https://c/cb" ])
      access, _, record = OauthToken.issue(client_id: client.client_id)
      record.update!(revoked_at: Time.current)

      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
                   headers: { "Authorization" => "Bearer #{access}", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with a valid Bearer token" do
    before { allow(Pito::Mcp::Auth).to receive(:authenticate).and_return(instance_double("OauthClient")) }

    describe "initialize" do
      it "returns the protocol version, tool capability, and server info" do
        body = rpc({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} })
        expect(body["result"]).to include("protocolVersion" => "2025-06-18")
        expect(body["result"]["capabilities"]).to have_key("tools")
        expect(body["result"]["serverInfo"]).to include("name" => "pito")
      end
    end

    describe "notifications/initialized (a notification)" do
      it "returns 202 with no body" do
        post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: headers
        expect(response).to have_http_status(:accepted)
        expect(response.body).to be_blank
      end
    end

    describe "tools/list" do
      it "returns every declared tool with a name, description, and inputSchema" do
        tools = rpc({ jsonrpc: "2.0", id: 2, method: "tools/list" })["result"]["tools"]
        expect(tools.size).to eq(Pito::Mcp::Registry.tool_names.size)
        expect(tools).to all(include("name", "description", "inputSchema"))
        expect(tools.map { |t| t["name"] }).to include("pito_list", "pito_conversations")
      end
    end

    describe "tools/call" do
      it "runs a tool and returns a text content block" do
        create(:game, title: "Hollow Knight")
        body = rpc({ jsonrpc: "2.0", id: 3, method: "tools/call",
                     params: { name: "pito_list", arguments: { noun: "games" } } })

        expect(body["result"]["isError"]).to be(false)
        expect(body["result"]["content"].first).to include("type" => "text")
        expect(body["result"]["content"].first["text"]).to include("Hollow Knight")
      end

      it "returns an invalid-params error for an unknown tool" do
        body = rpc({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "pito_nope", arguments: {} } })
        expect(body["error"]).to include("code" => -32_602)
        expect(body["error"]["message"]).to match(/unknown tool/i)
      end

      it "returns an invalid-params error when the tool name is missing" do
        body = rpc({ jsonrpc: "2.0", id: 5, method: "tools/call", params: {} })
        expect(body["error"]).to include("code" => -32_602)
      end
    end

    describe "ping" do
      it "returns an empty result" do
        expect(rpc({ jsonrpc: "2.0", id: 6, method: "ping" })["result"]).to eq({})
      end
    end

    describe "protocol errors" do
      it "returns method-not-found for an unknown method" do
        body = rpc({ jsonrpc: "2.0", id: 7, method: "does/not/exist" })
        expect(body["error"]).to include("code" => -32_601)
      end

      it "returns a parse error for malformed JSON" do
        body = rpc("{ not json")
        expect(body["error"]).to include("code" => -32_700)
      end

      it "returns an invalid-request error for a non-object body" do
        body = rpc("[1, 2, 3]")
        expect(body["error"]).to include("code" => -32_600)
      end

      it "echoes the request id in the response" do
        expect(rpc({ jsonrpc: "2.0", id: 99, method: "ping" })["id"]).to eq(99)
      end
    end
  end
end
