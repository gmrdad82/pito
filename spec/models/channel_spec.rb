require "rails_helper"

RSpec.describe Channel, type: :model do
  subject { build(:channel) }

  describe "associations" do
    it "does not declare a tenant association" do
      expect(Channel.reflect_on_association(:tenant)).to be_nil
    end
    it { is_expected.to have_many(:videos).dependent(:destroy) }
    it { is_expected.to have_many(:playlists).dependent(:destroy) }
    it { is_expected.to have_many(:video_uploads).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:channel_url) }

    describe "channel_url regex" do
      it "accepts the canonical example" do
        channel = build(:channel, channel_url: "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
        expect(channel).to be_valid
      end

      [
        "https://youtu.be/abc",
        "https://www.youtube.com/@handle",
        "https://www.youtube.com/c/foo",
        "https://www.youtube.com/user/foo",
        "http://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ",
        "https://youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ",
        "https://www.youtube.com/channel/UCshort",
        ""
      ].each do |bad|
        it "rejects #{bad.inspect}" do
          channel = build(:channel, channel_url: bad)
          expect(channel).not_to be_valid
          expect(channel.errors[:channel_url]).to be_present
        end
      end
    end

    describe "channel_url uniqueness (case-sensitive)" do
      it "rejects duplicate URLs" do
        url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
        create(:channel, channel_url: url)
        dup = build(:channel, channel_url: url)
        expect(dup).not_to be_valid
        expect(dup.errors[:channel_url]).to be_present
      end
    end
  end

  describe "URL lock on update" do
    it "raises Channel::UrlLockedError when channel_url changes" do
      channel = create(:channel)
      channel.channel_url = "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA"
      expect { channel.save }.to raise_error(Channel::UrlLockedError)
    end

    it "permits updates that do not touch channel_url" do
      channel = create(:channel)
      expect { channel.update!(star: true) }.not_to raise_error
      expect(channel.reload.star).to be(true)
    end
  end

  describe "scopes" do
    it ".starred returns only starred channels" do
      starred = create(:channel, :starred)
      _other  = create(:channel)
      expect(Channel.starred).to eq([ starred ])
    end

    it ".connected returns only channels with an oauth_identity" do
      connected = create(:channel, :connected)
      _other    = create(:channel)
      expect(Channel.connected).to eq([ connected ])
    end
  end

  describe "Phase 7 — oauth_identity association" do
    it "permits a NULL oauth_identity_id" do
      channel = create(:channel)
      expect(channel.oauth_identity).to be_nil
    end

    it "associates a GoogleIdentity to the Channel" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)
      expect(channel.reload.oauth_identity).to eq(identity)
    end
  end
end
