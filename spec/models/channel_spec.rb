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
    it { is_expected.to have_many(:channel_change_logs).dependent(:delete_all) }

    it "destroys channel_change_logs when the channel is destroyed" do
      user = create(:user)
      channel = create(:channel)
      log = ChannelChangeLog.create!(
        channel: channel, changed_by_user: user,
        field: "title", new_value: "New",
        changed_at: Time.current
      )
      expect { channel.destroy }
        .to change { ChannelChangeLog.where(id: log.id).count }.from(1).to(0)
    end
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

    # Phase 22 — the `.connected` scope was reintroduced with new
    # semantics: a channel is connected when it carries a
    # `youtube_connection_id` (the post-rename equivalent of the
    # Phase 9-era `connected` boolean). The import modal's channel
    # picker lists this scope.
    it "exposes a .connected scope scoped to channels with a youtube_connection_id" do
      expect(Channel).to respond_to(:connected)
    end
  end

  describe "Phase 9 — youtube_connection association" do
    it "permits a NULL youtube_connection_id" do
      channel = create(:channel)
      expect(channel.youtube_connection).to be_nil
    end

    it "associates a YoutubeConnection to the Channel" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)
      expect(channel.reload.youtube_connection).to eq(connection)
    end
  end

  describe "Phase 7.5 §11a — Channel resource validations" do
    let(:channel) { create(:channel) }

    describe "title" do
      it "permits blank" do
        channel.title = nil
        expect(channel).to be_valid
      end
      it "permits a 100-character title" do
        channel.title = "x" * 100
        expect(channel).to be_valid
      end
      it "rejects a 101-character title" do
        channel.title = "x" * 101
        expect(channel).not_to be_valid
        expect(channel.errors[:title]).to be_present
      end
    end

    describe "handle" do
      it "permits blank" do
        channel.handle = nil
        expect(channel).to be_valid
      end
      it "accepts @handles inside 3..30 chars and the allowed alphabet" do
        channel.handle = "@valid_handle.01-x"
        expect(channel).to be_valid
      end
      it "rejects a handle missing the leading @" do
        channel.handle = "novalid"
        expect(channel).not_to be_valid
      end
      it "rejects a too-short handle (`@a` is 2 chars)" do
        channel.handle = "@a"
        expect(channel).not_to be_valid
      end
      it "rejects a too-long handle (>30)" do
        channel.handle = "@" + ("a" * 30)
        expect(channel).not_to be_valid
      end
      it "rejects forbidden punctuation" do
        channel.handle = "@bad!handle"
        expect(channel).not_to be_valid
      end
    end

    describe "description" do
      it "permits blank" do
        channel.description = nil
        expect(channel).to be_valid
      end
      it "permits 5000 chars" do
        channel.description = "x" * 5000
        expect(channel).to be_valid
      end
      it "rejects 5001 chars" do
        channel.description = "x" * 5001
        expect(channel).not_to be_valid
      end
    end

    describe "country" do
      it "permits blank" do
        channel.country = nil
        expect(channel).to be_valid
      end
      it "accepts ISO 3166-1 alpha-2 uppercase" do
        channel.country = "US"
        expect(channel).to be_valid
      end
      it "rejects lowercase" do
        channel.country = "us"
        expect(channel).not_to be_valid
      end
      it "rejects three-letter codes" do
        channel.country = "USA"
        expect(channel).not_to be_valid
      end
    end

    describe "default_language" do
      it "permits blank" do
        channel.default_language = nil
        expect(channel).to be_valid
      end
      it "accepts `en`" do
        channel.default_language = "en"
        expect(channel).to be_valid
      end
      it "accepts `pt-BR`" do
        channel.default_language = "pt-BR"
        expect(channel).to be_valid
      end
      it "accepts a 3-letter primary subtag (e.g. `fil`)" do
        channel.default_language = "fil"
        expect(channel).to be_valid
      end
      it "rejects uppercased primary subtag" do
        channel.default_language = "EN"
        expect(channel).not_to be_valid
      end
      it "rejects lowercased region subtag" do
        channel.default_language = "en-us"
        expect(channel).not_to be_valid
      end
    end

    describe "watermark_timing" do
      it "permits blank" do
        channel.watermark_timing = nil
        expect(channel).to be_valid
      end
      Channel::WATERMARK_TIMINGS.each do |value|
        it "accepts `#{value}`" do
          channel.watermark_timing = value
          expect(channel).to be_valid
        end
      end
      it "rejects values outside the documented enum" do
        channel.watermark_timing = "forever"
        expect(channel).not_to be_valid
      end
    end

    describe "watermark_offset_ms" do
      it "permits blank" do
        channel.watermark_offset_ms = nil
        expect(channel).to be_valid
      end
      it "accepts zero" do
        channel.watermark_offset_ms = 0
        expect(channel).to be_valid
      end
      it "rejects negatives" do
        channel.watermark_offset_ms = -1
        expect(channel).not_to be_valid
      end
      it "rejects non-integers" do
        channel.watermark_offset_ms = 1.5
        expect(channel).not_to be_valid
      end
    end

    describe "subscriber_count / view_count / video_count" do
      it "permits blank for each" do
        channel.subscriber_count = nil
        channel.view_count = nil
        channel.video_count = nil
        expect(channel).to be_valid
      end
      it "rejects negatives on subscriber_count" do
        channel.subscriber_count = -1
        expect(channel).not_to be_valid
      end
      it "rejects negatives on view_count" do
        channel.view_count = -1
        expect(channel).not_to be_valid
      end
      it "rejects negatives on video_count" do
        channel.video_count = -1
        expect(channel).not_to be_valid
      end
    end

    describe "links shape validator" do
      it "accepts the empty array (default)" do
        channel.links = []
        expect(channel).to be_valid
      end

      it "accepts an array of valid {title, url} hashes" do
        channel.links = [
          { "title" => "Site", "url" => "https://example.com" },
          { "title" => "Twitch", "url" => "https://twitch.tv/me" }
        ]
        expect(channel).to be_valid
      end

      it "accepts symbol keys" do
        channel.links = [ { title: "Site", url: "https://example.com" } ]
        expect(channel).to be_valid
      end

      it "rejects >5 entries" do
        channel.links = Array.new(6) do |i|
          { "title" => "Link #{i}", "url" => "https://example.com/#{i}" }
        end
        expect(channel).not_to be_valid
        expect(channel.errors[:links]).to be_present
      end

      it "rejects entries missing the title" do
        channel.links = [ { "url" => "https://example.com" } ]
        expect(channel).not_to be_valid
      end

      it "rejects entries missing the url" do
        channel.links = [ { "title" => "Site" } ]
        expect(channel).not_to be_valid
      end

      it "rejects entries with a non-http(s) url" do
        channel.links = [ { "title" => "Site", "url" => "ftp://example.com" } ]
        expect(channel).not_to be_valid
      end

      it "rejects a non-Array input (string)" do
        channel.links = "not an array"
        expect(channel).not_to be_valid
      end

      it "rejects a non-Array input (Hash)" do
        channel.links = { "title" => "Site", "url" => "https://example.com" }
        expect(channel).not_to be_valid
      end

      it "rejects a title >50 chars" do
        channel.links = [ { "title" => "x" * 51, "url" => "https://example.com" } ]
        expect(channel).not_to be_valid
      end

      it "rejects a blank title" do
        channel.links = [ { "title" => "", "url" => "https://example.com" } ]
        expect(channel).not_to be_valid
      end
    end
  end

  describe "Phase 7.5 §11a — 14-day rate-limit gate helpers" do
    let(:channel) { create(:channel) }

    describe "#title_locked?" do
      it "is false when title_changed_at is nil" do
        channel.title_changed_at = nil
        expect(channel.title_locked?).to be(false)
      end

      it "is true at 13d 23h after the change" do
        channel.title_changed_at = (14.days - 1.hour).ago
        expect(channel.title_locked?).to be(true)
      end

      it "is false at exactly 14 days after the change" do
        channel.title_changed_at = 14.days.ago
        expect(channel.title_locked?).to be(false)
      end

      it "is false at 14d 1m after the change" do
        channel.title_changed_at = (14.days + 1.minute).ago
        expect(channel.title_locked?).to be(false)
      end
    end

    describe "#title_unlock_at" do
      it "returns nil when title_changed_at is nil" do
        channel.title_changed_at = nil
        expect(channel.title_unlock_at).to be_nil
      end

      it "returns title_changed_at + 14d while still locked" do
        stamp = (14.days - 1.hour).ago
        channel.title_changed_at = stamp
        expect(channel.title_unlock_at).to be_within(1.second).of(stamp + 14.days)
      end

      it "returns nil when the lock window has elapsed" do
        channel.title_changed_at = (14.days + 1.minute).ago
        expect(channel.title_unlock_at).to be_nil
      end
    end

    describe "#handle_locked?" do
      it "is false when handle_changed_at is nil" do
        channel.handle_changed_at = nil
        expect(channel.handle_locked?).to be(false)
      end

      it "is true at 13d 23h after the change" do
        channel.handle_changed_at = (14.days - 1.hour).ago
        expect(channel.handle_locked?).to be(true)
      end

      it "is false at exactly 14 days after the change" do
        channel.handle_changed_at = 14.days.ago
        expect(channel.handle_locked?).to be(false)
      end

      it "is false at 14d 1m after the change" do
        channel.handle_changed_at = (14.days + 1.minute).ago
        expect(channel.handle_locked?).to be(false)
      end
    end

    describe "#handle_unlock_at" do
      it "returns nil when handle_changed_at is nil" do
        expect(channel.handle_unlock_at).to be_nil
      end

      it "returns handle_changed_at + 14d while still locked" do
        stamp = (14.days - 1.hour).ago
        channel.handle_changed_at = stamp
        expect(channel.handle_unlock_at).to be_within(1.second).of(stamp + 14.days)
      end

      it "returns nil when the lock window has elapsed" do
        channel.handle_changed_at = (14.days + 1.minute).ago
        expect(channel.handle_unlock_at).to be_nil
      end
    end
  end

  # Phase 22 — Video Import Flow associations + helpers.
  describe "import flow associations" do
    it { is_expected.to have_many(:import_jobs).dependent(:destroy) }
    it { is_expected.to have_many(:rejected_video_imports).dependent(:destroy) }

    it "cascades import_jobs on destroy" do
      channel = create(:channel)
      user = create(:user)
      job = ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
      expect { channel.destroy }
        .to change { ImportJob.where(id: job.id).count }.from(1).to(0)
    end

    it "cascades rejected_video_imports on destroy" do
      channel = create(:channel)
      user = create(:user)
      row = create(:rejected_video_import, channel: channel, rejected_by: user)
      expect { channel.destroy }
        .to change { RejectedVideoImport.where(id: row.id).count }.from(1).to(0)
    end
  end

  describe ".connected scope" do
    it "includes channels with a youtube_connection_id" do
      conn = create(:youtube_connection)
      with_conn = create(:channel, youtube_connection: conn)
      without_conn = create(:channel)
      expect(Channel.connected).to include(with_conn)
      expect(Channel.connected).not_to include(without_conn)
    end
  end

  describe "#in_flight_import?" do
    let(:channel) { create(:channel) }
    let(:user)    { create(:user) }

    it "is true when a queued ImportJob exists" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
      expect(channel.in_flight_import?).to be(true)
    end

    it "is true when a running ImportJob exists" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      expect(channel.in_flight_import?).to be(true)
    end

    it "is false when only terminal-state jobs exist" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :completed,
                        started_at: 1.minute.ago, completed_at: Time.current)
      ImportJob.create!(channel: channel, enqueued_by: user, status: :failed,
                        started_at: 1.minute.ago, completed_at: Time.current,
                        error_payload: { "code" => "boom" })
      expect(channel.in_flight_import?).to be(false)
    end

    it "is false with no jobs" do
      expect(channel.in_flight_import?).to be(false)
    end
  end

  describe "#in_flight_import_job" do
    let(:channel) { create(:channel) }
    let(:user)    { create(:user) }

    it "returns the most recent in-flight job" do
      _older = ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      newer  = ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
      expect(channel.in_flight_import_job).to eq(newer)
    end

    it "returns nil when no in-flight job exists" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :completed,
                        started_at: 1.minute.ago, completed_at: Time.current)
      expect(channel.in_flight_import_job).to be_nil
    end
  end
end
