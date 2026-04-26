require "rails_helper"

RSpec.describe Channel, type: :model do
  subject { build(:channel) }

  describe "associations" do
    it { is_expected.to have_many(:videos).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:youtube_channel_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_channel_id).case_insensitive }
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "scopes" do
    it ".connected returns only connected channels" do
      connected = create(:channel, :connected)
      _public = create(:channel)
      expect(Channel.connected).to eq([ connected ])
    end

    it ".public_only returns only non-connected channels" do
      _connected = create(:channel, :connected)
      public_ch = create(:channel)
      expect(Channel.public_only).to eq([ public_ch ])
    end
  end

  describe "encryption" do
    it "encrypts oauth tokens" do
      channel = create(:channel, oauth_access_token: "token123", oauth_refresh_token: "refresh456")
      raw = Channel.connection.select_one(
        "SELECT oauth_access_token, oauth_refresh_token FROM channels WHERE id = #{channel.id}"
      )
      expect(raw["oauth_access_token"]).not_to eq("token123")
      expect(raw["oauth_refresh_token"]).not_to eq("refresh456")

      channel.reload
      expect(channel.oauth_access_token).to eq("token123")
      expect(channel.oauth_refresh_token).to eq("refresh456")
    end
  end
end
