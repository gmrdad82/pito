require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_create"

RSpec.describe Mcp::Tools::BundleCreate do
  it "preview when confirm: no — no row created" do
    expect {
      described_class.call(name: "X", bundle_type: "custom", confirm: "no")
    }.not_to change(Bundle, :count)
  end

  it "creates a custom bundle with confirm: yes" do
    expect {
      described_class.call(name: "Soulslikes", bundle_type: "custom", confirm: "yes")
    }.to change(Bundle, :count).by(1)
    expect(Bundle.last.name).to eq("Soulslikes")
  end

  it "creates a series bundle with igdb_source" do
    described_class.call(name: "Zelda series",
                         bundle_type: "series",
                         igdb_source_type: "franchise",
                         igdb_source_id: 42,
                         confirm: "yes")
    expect(Bundle.last.igdb_source_id).to eq(42)
  end

  it "rejects unknown bundle_type" do
    result = described_class.call(name: "x", bundle_type: "garbage", confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(name: "x", bundle_type: "custom", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(name: "x", bundle_type: "custom", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
