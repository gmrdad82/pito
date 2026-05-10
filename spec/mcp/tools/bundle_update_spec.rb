require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_update"

RSpec.describe Mcp::Tools::BundleUpdate do
  let!(:bundle) { create(:bundle, name: "Old") }

  it "preview when confirm: no" do
    described_class.call(id: bundle.id, name: "New", confirm: "no")
    expect(bundle.reload.name).to eq("Old")
  end

  it "updates the name with confirm: yes" do
    described_class.call(id: bundle.id, name: "New", confirm: "yes")
    expect(bundle.reload.name).to eq("New")
  end

  it "404s on missing bundle" do
    result = described_class.call(id: 999_999, name: "x", confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: bundle.id, name: "x", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: bundle.id, name: "x", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
