require "rails_helper"

# Phase 10 — MCP scope simplification (ADR 0004).
#
# `Mcp::ToolAuth.require_scope!` enforces the per-tool scope check via
# a literal lookup in `Current.token.scopes`. The helper is generic
# (it accepts any scope string), so the catalog collapse from 9 to 2
# entries does NOT change its API. This spec exercises the new
# happy-path / sad-path matrix and the legacy-string defense-in-depth.
RSpec.describe Mcp::ToolAuth do
  let(:user) { User.first || create(:user) }

  def with_token(scopes:)
    record, _plaintext = ApiToken.generate!(
      user: user, name: "tool-auth-spec-#{rand(1_000_000)}", scopes: scopes
    )
    Current.token = record
  end

  describe ".require_scope!" do
    it "returns nil when the token carries the requested scope" do
      with_token(scopes: [ Scopes::DEV ])
      expect(described_class.require_scope!(Scopes::DEV)).to be_nil
    end

    it "returns an insufficient_scope Response when the token lacks the scope" do
      with_token(scopes: [ Scopes::APP ])
      response = described_class.require_scope!(Scopes::DEV)
      expect(response).to be_a(MCP::Tool::Response)
      payload = JSON.parse(response.content.first[:text])
      expect(payload["error"]).to eq("insufficient_scope")
      expect(payload["required"]).to eq("dev")
    end

    it "returns an insufficient_scope Response when Current.token is nil" do
      Current.token = nil
      response = described_class.require_scope!(Scopes::APP)
      expect(response).to be_a(MCP::Tool::Response)
    end

    it "rejects a request when the token's scopes only contain a legacy string" do
      # Defense-in-depth: simulate a stale token (the model validation
      # would reject this on save, but a hand-crafted SQL update could
      # smuggle the row through).
      record, _plaintext = ApiToken.generate!(
        user: user, name: "legacy", scopes: [ Scopes::DEV ]
      )
      record.update_columns(scopes: [ "dev:read" ])
      Current.token = record

      response = described_class.require_scope!(Scopes::DEV)
      expect(response).to be_a(MCP::Tool::Response)
      payload = JSON.parse(response.content.first[:text])
      expect(payload["error"]).to eq("insufficient_scope")
    end
  end
end
