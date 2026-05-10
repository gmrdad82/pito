require "rails_helper"

# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# YoutubeApiCall belongs_to :youtube_connection (renamed from
# :google_identity).
RSpec.describe YoutubeApiCall, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:youtube_connection).optional }
    it "does not declare a tenant association" do
      expect(YoutubeApiCall.reflect_on_association(:tenant)).to be_nil
    end
    it "does not declare a google_identity association" do
      expect(YoutubeApiCall.reflect_on_association(:google_identity)).to be_nil
    end
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
      connection = create(:youtube_connection)
      recent = create(:youtube_api_call, youtube_connection: connection, created_at: Time.current)
      old = create(:youtube_api_call, youtube_connection: connection, created_at: 2.days.ago)

      ids = YoutubeApiCall.today.pluck(:id)
      expect(ids).to include(recent.id)
      expect(ids).not_to include(old.id)
    end
  end
end
