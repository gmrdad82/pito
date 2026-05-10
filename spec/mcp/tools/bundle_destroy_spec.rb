require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_destroy"

RSpec.describe Mcp::Tools::BundleDestroy do
  let!(:bundle) { create(:bundle, name: "Toast") }

  it "preview when confirm: no — bundle survives" do
    described_class.call(id: bundle.id, confirm: "no")
    expect(Bundle.where(id: bundle.id)).to exist
  end

  it "destroys with confirm: yes" do
    described_class.call(id: bundle.id, confirm: "yes")
    expect(Bundle.where(id: bundle.id)).not_to exist
  end

  it "404s on missing bundle" do
    result = described_class.call(id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: bundle.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: bundle.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
