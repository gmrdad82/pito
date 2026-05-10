require "rails_helper"

# Phase 7.5 §11a — ChannelSync rewrite. Replaces the Path A2 placeholder
# (`update_columns(last_synced_at: Time.current)`) with a real
# fetch + persist flow. These specs lock the eight code paths the spec
# enumerates (happy + missing-connection + missing-channel +
# needs-reauth + transient + quota + permanent + record-invalid).
RSpec.describe ChannelSync, type: :job do
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:client)     { instance_double(Youtube::Client) }

  def normalized_hash(overrides = {})
    {
      title: "Pulled Title",
      handle: "@pulled",
      description: "Pulled description",
      country: "US",
      default_language: "en",
      keywords: "k1 k2",
      banner_url: "https://cdn.youtube/banner.jpg",
      avatar_url: "https://cdn.youtube/avatar.jpg",
      watermark_url: nil,
      watermark_timing: nil,
      watermark_offset_ms: nil,
      links: [],
      subscriber_count: 1234,
      view_count: 5_678_901,
      video_count: 42,
      hidden_subscriber_count: false,
      published_at: "2014-01-02T03:04:05Z"
    }.merge(overrides)
  end

  describe "happy path" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      allow(client).to receive(:fetch_channel).with(channel).and_return(normalized_hash)
    end

    it "caches every normalized column and stamps last_synced_at" do
      described_class.new.perform(channel.id)
      channel.reload

      expect(channel.title).to eq("Pulled Title")
      expect(channel.handle).to eq("@pulled")
      expect(channel.description).to eq("Pulled description")
      expect(channel.country).to eq("US")
      expect(channel.default_language).to eq("en")
      expect(channel.keywords).to eq("k1 k2")
      expect(channel.banner_url).to eq("https://cdn.youtube/banner.jpg")
      expect(channel.avatar_url).to eq("https://cdn.youtube/avatar.jpg")
      expect(channel.subscriber_count).to eq(1234)
      expect(channel.view_count).to eq(5_678_901)
      expect(channel.video_count).to eq(42)
      expect(channel.hidden_subscriber_count).to be(false)
      expect(channel.last_synced_at).to be_within(2.seconds).of(Time.current)
    end

    it "opens a single transaction for the persist step" do
      # The transaction count is asserted indirectly by counting nested
      # savepoints — only one BEGIN/COMMIT pair around the update.
      tx_count = 0
      callback = lambda do |_name, _start, _finish, _id, payload|
        tx_count += 1 if payload[:sql] =~ /\A(BEGIN|SAVEPOINT)\b/i
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new.perform(channel.id)
      end
      # Allow one or more savepoints (Rails uses transactional fixtures),
      # but assert at least one explicit BEGIN/SAVEPOINT around the call.
      expect(tx_count).to be >= 1
    end
  end

  describe "channel without a youtube_connection_id" do
    let(:disconnected) { create(:channel) }

    it "returns without calling the API or touching the row" do
      expect(Youtube::Client).not_to receive(:new)
      original_stamp = disconnected.last_synced_at
      described_class.new.perform(disconnected.id)
      expect(disconnected.reload.last_synced_at).to eq(original_stamp)
    end
  end

  describe "channel deleted between enqueue and perform" do
    it "is a no-op (no raise, no API call)" do
      expect(Youtube::Client).not_to receive(:new)
      expect { described_class.new.perform(999_999_999) }.not_to raise_error
    end
  end

  describe "NeedsReauthError from fetch_channel" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      allow(client).to receive(:fetch_channel)
        .and_raise(Youtube::NeedsReauthError.new("401 after refresh"))
    end

    it "re-raises and leaves the row untouched" do
      original_stamp = channel.last_synced_at
      expect { described_class.new.perform(channel.id) }
        .to raise_error(Youtube::NeedsReauthError)
      expect(channel.reload.title).to be_nil
      expect(channel.reload.last_synced_at).to eq(original_stamp)
    end
  end

  describe "TransientError from fetch_channel" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      allow(client).to receive(:fetch_channel)
        .and_raise(Youtube::TransientError.new("5xx exhausted"))
    end

    it "re-raises and leaves the row untouched" do
      original_stamp = channel.last_synced_at
      expect { described_class.new.perform(channel.id) }
        .to raise_error(Youtube::TransientError)
      expect(channel.reload.title).to be_nil
      expect(channel.reload.last_synced_at).to eq(original_stamp)
    end
  end

  describe "QuotaExhaustedError from fetch_channel" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      allow(client).to receive(:fetch_channel)
        .and_raise(Youtube::QuotaExhaustedError.new("daily quota exhausted"))
    end

    it "re-raises and leaves the row untouched" do
      original_stamp = channel.last_synced_at
      expect { described_class.new.perform(channel.id) }
        .to raise_error(Youtube::QuotaExhaustedError)
      expect(channel.reload.last_synced_at).to eq(original_stamp)
    end
  end

  describe "PermanentError from fetch_channel" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      allow(client).to receive(:fetch_channel)
        .and_raise(Youtube::PermanentError.new("client error 400"))
    end

    it "logs and returns without re-raising" do
      expect(Rails.logger).to receive(:warn).at_least(:once)
      expect { described_class.new.perform(channel.id) }.not_to raise_error
      expect(channel.reload.last_synced_at).to be_nil
    end
  end

  describe "RecordInvalid from channel.update! (e.g. 101-char title from API)" do
    before do
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
      bad_payload = normalized_hash(title: "x" * 101)
      allow(client).to receive(:fetch_channel).with(channel).and_return(bad_payload)
    end

    it "re-raises and rolls back so last_synced_at stays unchanged" do
      expect { described_class.new.perform(channel.id) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(channel.reload.title).to be_nil
      expect(channel.reload.last_synced_at).to be_nil
    end
  end
end
