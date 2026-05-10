require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_search"

RSpec.describe Mcp::Tools::BundleSearch do
  it "returns matching bundles" do
    create(:bundle, name: "Soulslikes")
    create(:bundle, name: "Cozy Games")
    result = described_class.call(q: "souls")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed.map { |r| r["name"] }).to eq([ "Soulslikes" ])
  end

  it "returns top bundles when q is empty" do
    create(:bundle, name: "B1")
    result = described_class.call(q: "")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed.map { |r| r["name"] }).to include("B1")
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(q: "anything")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
