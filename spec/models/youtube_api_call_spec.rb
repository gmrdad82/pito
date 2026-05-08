require "rails_helper"

RSpec.describe YoutubeApiCall, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:google_identity).optional }
  end

  describe "validations" do
    subject { build(:youtube_api_call) }

    it { is_expected.to validate_presence_of(:client_kind) }
    it { is_expected.to validate_inclusion_of(:client_kind).in_array(%w[oauth public]) }
    it { is_expected.to validate_presence_of(:endpoint) }
    it { is_expected.to validate_presence_of(:http_method) }
    it { is_expected.to validate_presence_of(:units) }
    it { is_expected.to validate_inclusion_of(:outcome).in_array(YoutubeApiCall::OUTCOMES) }
  end

  describe ".today" do
    it "returns rows created today" do
      identity = create(:google_identity)
      recent = create(:youtube_api_call, google_identity: identity, created_at: Time.current)
      old = create(:youtube_api_call, google_identity: identity, created_at: 2.days.ago)

      ids = YoutubeApiCall.today.pluck(:id)
      expect(ids).to include(recent.id)
      expect(ids).not_to include(old.id)
    end
  end

  describe "tenant scoping" do
    it "is not visible to a different tenant" do
      identity = create(:google_identity)
      row = create(:youtube_api_call, google_identity: identity)

      tenant_b = create(:tenant, slug: "other-tenant-yt", name: "other")
      Current.tenant = tenant_b
      expect(YoutubeApiCall.where(id: row.id)).to be_empty
    end
  end
end
