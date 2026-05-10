require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_seed_from_igdb"

RSpec.describe Mcp::Tools::BundleSeedFromIgdb do
  let!(:bundle) { create(:bundle, :series) }

  it "rejects custom bundles (no IGDB source)" do
    custom = create(:bundle, bundle_type: :custom)
    result = described_class.call(id: custom.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing bundle" do
    result = described_class.call(id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "preview when confirm: no — no API call" do
    expect_any_instance_of(Igdb::Client).not_to receive(:fetch_games_for_franchise)
    described_class.call(id: bundle.id, confirm: "no")
  end

  it "calls IGDB and adds members with confirm: yes" do
    fake_client = instance_double(Igdb::Client)
    allow(Igdb::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:fetch_games_for_franchise).and_return([
      { "id" => 7346, "name" => "Zelda BotW" }
    ])

    expect {
      described_class.call(id: bundle.id, confirm: "yes")
    }.to change(BundleMember, :count).by(1)
    expect(Game.find_by(igdb_id: 7346)).to be_present
  end

  it "stamps last_error on Igdb::Client::Error" do
    fake_client = instance_double(Igdb::Client)
    allow(Igdb::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:fetch_games_for_franchise).and_raise(Igdb::Client::Error.new("boom"))

    described_class.call(id: bundle.id, confirm: "yes")
    expect(bundle.reload.last_error).to include("boom")
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
