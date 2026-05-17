require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_create"

# Phase 14 §3 / Phase 27 follow-up (2026-05-17) — `bundle_create` MCP
# tool spec. After the 2026-05-17 simplification the tool accepts
# only `name` (plus the standard `confirm` two-step). The legacy
# `bundle_type` / `igdb_source_*` inputs are gone.
RSpec.describe Mcp::Tools::BundleCreate do
  it "preview when confirm: no — no row created" do
    expect {
      described_class.call(name: "X", confirm: "no")
    }.not_to change(Bundle, :count)
  end

  it "creates a bundle with confirm: yes" do
    expect {
      described_class.call(name: "Soulslikes", confirm: "yes")
    }.to change(Bundle, :count).by(1)
    expect(Bundle.last.name).to eq("Soulslikes")
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(name: "x", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(name: "x", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
