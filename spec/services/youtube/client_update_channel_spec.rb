require "rails_helper"
require "ostruct"

# Phase 7.5 §11c — Channel edit form. Exercises the three destructive
# entrypoints on `Youtube::Client` (`#update_channel`, `#set_watermark`,
# `#unset_watermark`) against the same canned-response / canned-error
# pattern the rest of the client specs use. The audit + retry / refresh
# / quota plumbing lives in `client_spec.rb`; this spec asserts (1) the
# call shape (read-modify-write for update_channel, single POST for
# watermarks), (2) the response shape, (3) the error taxonomy.
RSpec.describe Youtube::Client do
  let(:connection) { create(:youtube_connection) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           youtube_connection: connection)
  end
  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

  def stub_data_service(svc_double)
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc_double)
    allow(svc_double).to receive(:client_options).and_return(
      Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil)
    )
    allow(svc_double).to receive(:authorization=)
  end

  def existing_branding_response(overrides = {})
    OpenStruct.new(
      items: [
        OpenStruct.new(
          id: "UCabcabcabcabcabcabcabcA",
          branding_settings: OpenStruct.new(
            channel: OpenStruct.new(
              {
                title: "Existing Title",
                description: "Existing description",
                country: "US",
                default_language: "en",
                keywords: "gaming reviews"
              }.merge(overrides)
            )
          )
        )
      ],
      next_page_token: nil
    )
  end

  def update_channel_response
    OpenStruct.new(
      id: "UCabcabcabcabcabcabcabcA",
      snippet: OpenStruct.new(
        title: "New Title",
        custom_url: "@maincreator",
        description: "New description",
        country: "US",
        default_language: "en"
      ),
      statistics: OpenStruct.new(subscriber_count: "1234", view_count: "5678901", video_count: "42"),
      branding_settings: OpenStruct.new(
        channel: OpenStruct.new(
          title: "New Title",
          description: "New description",
          country: "US",
          default_language: "en",
          keywords: "gaming reviews"
        )
      )
    )
  end

  describe "#update_channel (happy path)" do
    before do
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(existing_branding_response)
      allow(svc).to receive(:update_channel).and_return(update_channel_response)
    end

    it "fires `channels.list` first (read), then `channels.update` (modify-write)" do
      described_class.new(connection).update_channel(channel, title: "New Title")
      expect(svc).to have_received(:list_channels).ordered
      expect(svc).to have_received(:update_channel).ordered
    end

    it "passes the merged branding payload (title overridden, siblings preserved)" do
      described_class.new(connection).update_channel(channel, title: "New Title")
      expect(svc).to have_received(:update_channel) do |part, channel_obj, *|
        expect(part).to eq("brandingSettings")
        merged = channel_obj.branding_settings.channel
        expect(merged.title).to eq("New Title")
        expect(merged.country).to eq("US")        # preserved
        expect(merged.default_language).to eq("en") # preserved
        expect(merged.keywords).to eq("gaming reviews") # preserved
      end
    end

    it "returns a snake_case Ruby Hash (never a Google::Apis struct)" do
      result = described_class.new(connection).update_channel(channel, title: "New Title")
      expect(result).to be_a(Hash)
      expect(result).to include(title: "New Title")
      expect(result).not_to be_a(Google::Apis::YoutubeV3::Channel)
    end

    it "supports multi-field dirty subsets (title + description + country)" do
      described_class.new(connection).update_channel(
        channel,
        title: "New Title",
        description: "New description",
        country: "DE"
      )
      expect(svc).to have_received(:update_channel) do |_part, channel_obj, *|
        merged = channel_obj.branding_settings.channel
        expect(merged.title).to eq("New Title")
        expect(merged.description).to eq("New description")
        expect(merged.country).to eq("DE")
      end
    end

    it "writes two audit rows (one channels.list, one channels.update)" do
      expect {
        described_class.new(connection).update_channel(channel, title: "New Title")
      }.to change { YoutubeApiCall.unscoped.count }.by(2)

      endpoints = YoutubeApiCall.unscoped.last(2).map(&:endpoint)
      expect(endpoints).to contain_exactly("channels.list", "channels.update")
      expect(YoutubeApiCall.unscoped.where(endpoint: "channels.update").last.units).to eq(50)
    end
  end

  describe "#update_channel argument validation" do
    it "raises ArgumentError when field_set is empty" do
      expect {
        described_class.new(connection).update_channel(channel, {})
      }.to raise_error(ArgumentError, /no supported keys/)
    end

    it "raises ArgumentError when field_set has only unsupported keys" do
      expect {
        described_class.new(connection).update_channel(channel, foo: "bar")
      }.to raise_error(ArgumentError, /no supported keys/)
    end

    it "raises ArgumentError when channel.channel_url has no UC id" do
      bad_channel = build_stubbed(:channel, channel_url: "https://example.test/no-id")
      stub_data_service(svc)
      expect {
        described_class.new(connection).update_channel(bad_channel, title: "x")
      }.to raise_error(ArgumentError, /channel id/)
    end
  end

  describe "#update_channel (sad paths)" do
    before { stub_data_service(svc) }

    it "raises QuotaExhaustedError when the pre-call budget refuses" do
      allow(Youtube::Quota).to receive(:budget_remaining).and_return(0)
      expect {
        described_class.new(connection).update_channel(channel, title: "x")
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises NeedsReauthError when 401 persists after refresh" do
      allow(svc).to receive(:list_channels).and_return(existing_branding_response)
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new(
        "Unauthorized", status_code: 401, body: '{"error":"invalid_token"}'
      )
      allow(svc).to receive(:update_channel).and_raise(err)

      expect {
        described_class.new(connection).update_channel(channel, title: "x")
      }.to raise_error(Youtube::NeedsReauthError)
      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "raises QuotaExhaustedError when YouTube returns 403 quotaExceeded" do
      allow(svc).to receive(:list_channels).and_return(existing_branding_response)
      err = Google::Apis::ClientError.new(
        "Quota exceeded",
        status_code: 403,
        body: '{"error":{"errors":[{"reason":"quotaExceeded"}]}}'
      )
      allow(svc).to receive(:update_channel).and_raise(err)

      expect {
        described_class.new(connection).update_channel(channel, title: "x")
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises TransientError after MAX_5XX_ATTEMPTS 5xx responses" do
      allow(svc).to receive(:list_channels).and_return(existing_branding_response)
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("Internal", status_code: 500, body: "{}")
      allow(svc).to receive(:update_channel).and_raise(err)

      expect {
        described_class.new(connection).update_channel(channel, title: "x")
      }.to raise_error(Youtube::TransientError)
    end
  end

  describe "#set_watermark (happy path)" do
    let(:fake_io) do
      OpenStruct.new(
        read: "fake_png_bytes",
        content_type: "image/png",
        original_filename: "watermark.png"
      )
    end

    before do
      stub_data_service(svc)
      allow(svc).to receive(:set_watermark).and_return(nil)
    end

    it "fires `watermarks.set` with the YouTube channel id and an InvideoBranding body" do
      described_class.new(connection).set_watermark(channel, fake_io, "always")
      expect(svc).to have_received(:set_watermark) do |yt_channel_id, branding, **kwargs|
        expect(yt_channel_id).to eq("UCabcabcabcabcabcabcabcA")
        expect(branding).to be_a(Google::Apis::YoutubeV3::InvideoBranding)
        expect(branding.timing.type).to eq("always")
        expect(kwargs[:upload_source]).to eq(fake_io)
        expect(kwargs[:content_type]).to eq("image/png")
      end
    end

    it "supports `entire_video` timing" do
      described_class.new(connection).set_watermark(channel, fake_io, "entire_video")
      expect(svc).to have_received(:set_watermark) do |_id, branding, **|
        expect(branding.timing.type).to eq("entireVideo")
        expect(branding.timing.offset_ms).to be_nil
      end
    end

    it "supports `offset_from_start` with required offset_ms" do
      described_class.new(connection).set_watermark(channel, fake_io, "offset_from_start", 5_000)
      expect(svc).to have_received(:set_watermark) do |_id, branding, **|
        expect(branding.timing.type).to eq("offsetFromStart")
        expect(branding.timing.offset_ms).to eq(5_000)
      end
    end

    it "supports `offset_from_end` with required offset_ms" do
      described_class.new(connection).set_watermark(channel, fake_io, "offset_from_end", 2_500)
      expect(svc).to have_received(:set_watermark) do |_id, branding, **|
        expect(branding.timing.type).to eq("offsetFromEnd")
        expect(branding.timing.offset_ms).to eq(2_500)
      end
    end

    it "raises ArgumentError when offset_ms is missing for offset timing" do
      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "offset_from_start", nil)
      }.to raise_error(ArgumentError, /offset_ms required/)
    end

    it "raises ArgumentError on unknown timing value" do
      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "noon")
      }.to raise_error(ArgumentError, /unknown timing/)
    end

    it "writes one audit row with endpoint=watermarks.set, cost=50" do
      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "always")
      }.to change { YoutubeApiCall.unscoped.count }.by(1)
      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("watermarks.set")
      expect(row.units).to eq(50)
      expect(row.outcome).to eq("success")
    end
  end

  describe "#set_watermark (sad paths)" do
    let(:fake_io) do
      OpenStruct.new(read: "x", content_type: "image/png", original_filename: "wm.png")
    end

    before { stub_data_service(svc) }

    it "raises QuotaExhaustedError when pre-call budget refuses" do
      allow(Youtube::Quota).to receive(:budget_remaining).and_return(0)
      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "always")
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises NeedsReauthError on 401 after refresh" do
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new(
        "Unauthorized", status_code: 401, body: '{"error":"invalid_token"}'
      )
      allow(svc).to receive(:set_watermark).and_raise(err)

      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "always")
      }.to raise_error(Youtube::NeedsReauthError)
    end

    it "raises TransientError after exhausted 5xx attempts" do
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("Internal", status_code: 500, body: "{}")
      allow(svc).to receive(:set_watermark).and_raise(err)
      expect {
        described_class.new(connection).set_watermark(channel, fake_io, "always")
      }.to raise_error(Youtube::TransientError)
    end
  end

  describe "#unset_watermark (happy path)" do
    before do
      stub_data_service(svc)
      allow(svc).to receive(:unset_watermark).and_return(nil)
    end

    it "fires `watermarks.unset` with the YouTube channel id" do
      described_class.new(connection).unset_watermark(channel)
      expect(svc).to have_received(:unset_watermark).with("UCabcabcabcabcabcabcabcA")
    end

    it "writes one audit row with endpoint=watermarks.unset, cost=50, outcome=success" do
      expect {
        described_class.new(connection).unset_watermark(channel)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)
      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("watermarks.unset")
      expect(row.units).to eq(50)
      expect(row.outcome).to eq("success")
    end
  end

  describe "#unset_watermark (sad paths)" do
    before { stub_data_service(svc) }

    it "raises QuotaExhaustedError when pre-call budget refuses" do
      allow(Youtube::Quota).to receive(:budget_remaining).and_return(0)
      expect {
        described_class.new(connection).unset_watermark(channel)
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises NeedsReauthError on 401 after refresh" do
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new(
        "Unauthorized", status_code: 401, body: '{"error":"invalid_token"}'
      )
      allow(svc).to receive(:unset_watermark).and_raise(err)

      expect {
        described_class.new(connection).unset_watermark(channel)
      }.to raise_error(Youtube::NeedsReauthError)
    end
  end
end
