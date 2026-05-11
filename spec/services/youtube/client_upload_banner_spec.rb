require "rails_helper"
require "ostruct"

# Phase 7.5 §11f — Channel banner upload. Exercises the two-step
# `Youtube::Client#upload_banner` entrypoint:
#
#   Step 1: `channelBanners.insert` — uploads the image bytes,
#           returns `ChannelBannerResource#url` (the opaque token
#           YouTube calls `bannerExternalUrl`).
#   Step 2: `channels.update` (part=brandingSettings) — sets
#           `brandingSettings.image.bannerExternalUrl = <token>`
#           to publish the banner. Response carries the cacheable
#           CDN URL under the same key.
#
# The audit + retry / refresh / quota plumbing lives in the shared
# `perform` chokepoint (see `client_spec.rb`); this spec asserts:
#
#   (1) Step 1 fires first, Step 2 fires second, with the right
#       body shape on each.
#   (2) Two audit rows are written (one per endpoint).
#   (3) The return value is the published banner URL string.
#   (4) Error taxonomy: 401-after-refresh → NeedsReauthError,
#       403 quotaExceeded → QuotaExhaustedError, 5xx → TransientError,
#       400 imageDimensionsInvalid → PermanentError.
RSpec.describe Youtube::Client, "#upload_banner" do
  let(:connection) { create(:youtube_connection) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           youtube_connection: connection)
  end
  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }
  let(:fake_io) do
    OpenStruct.new(
      read: "fake_jpeg_bytes",
      content_type: "image/jpeg",
      original_filename: "banner.jpg"
    )
  end

  def stub_data_service(svc_double)
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc_double)
    allow(svc_double).to receive(:client_options).and_return(
      Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil)
    )
    allow(svc_double).to receive(:authorization=)
  end

  def insert_banner_response(token: "https://upload.youtube/banner-token-123")
    OpenStruct.new(
      kind: "youtube#channelBannerResource",
      url: token
    )
  end

  def branding_read_response
    OpenStruct.new(
      items: [
        OpenStruct.new(
          id: "UCabcabcabcabcabcabcabcA",
          branding_settings: OpenStruct.new(
            channel: OpenStruct.new(
              title: "Existing Title",
              description: "Existing description",
              country: "US",
              default_language: "en",
              keywords: "gaming reviews"
            )
          )
        )
      ],
      next_page_token: nil
    )
  end

  def update_banner_response(cdn_url: "https://yt3.googleusercontent.com/abc/banner.jpg")
    OpenStruct.new(
      id: "UCabcabcabcabcabcabcabcA",
      snippet: OpenStruct.new(title: "Existing Title", description: "Existing description"),
      statistics: OpenStruct.new(subscriber_count: "1234", view_count: "5678", video_count: "42"),
      branding_settings: OpenStruct.new(
        channel: OpenStruct.new(
          title: "Existing Title",
          description: "Existing description",
          country: "US",
          default_language: "en",
          keywords: "gaming reviews"
        ),
        image: OpenStruct.new(banner_external_url: cdn_url)
      )
    )
  end

  describe "happy path" do
    before do
      stub_data_service(svc)
      allow(svc).to receive(:insert_channel_banner).and_return(insert_banner_response)
      allow(svc).to receive(:list_channels).and_return(branding_read_response)
      allow(svc).to receive(:update_channel).and_return(update_banner_response)
    end

    it "fires `channelBanners.insert` first, then `channels.list` + `channels.update`" do
      described_class.new(connection).upload_banner(channel, fake_io)
      expect(svc).to have_received(:insert_channel_banner).ordered
      expect(svc).to have_received(:list_channels).ordered
      expect(svc).to have_received(:update_channel).ordered
    end

    it "passes the IO + content_type to `channelBanners.insert`" do
      described_class.new(connection).upload_banner(channel, fake_io)
      expect(svc).to have_received(:insert_channel_banner) do |resource, **kwargs|
        expect(resource).to be_a(Google::Apis::YoutubeV3::ChannelBannerResource)
        expect(kwargs[:upload_source]).to eq(fake_io)
        expect(kwargs[:content_type]).to eq("image/jpeg")
      end
    end

    it "defaults content_type to image/jpeg when the IO has none" do
      io_without_ct = OpenStruct.new(read: "x", original_filename: "banner.jpg")
      described_class.new(connection).upload_banner(channel, io_without_ct)
      expect(svc).to have_received(:insert_channel_banner) do |_resource, **kwargs|
        expect(kwargs[:content_type]).to eq("image/jpeg")
      end
    end

    it "passes the insert-call token into `channels.update`'s image.banner_external_url" do
      described_class.new(connection).upload_banner(channel, fake_io)
      expect(svc).to have_received(:update_channel) do |part, channel_obj, *|
        expect(part).to eq("brandingSettings")
        image = channel_obj.branding_settings.image
        expect(image).to be_a(Google::Apis::YoutubeV3::ImageSettings)
        expect(image.banner_external_url).to eq("https://upload.youtube/banner-token-123")
      end
    end

    it "preserves the existing channel section (read-modify-write)" do
      described_class.new(connection).upload_banner(channel, fake_io)
      expect(svc).to have_received(:update_channel) do |_part, channel_obj, *|
        section = channel_obj.branding_settings.channel
        expect(section.title).to eq("Existing Title")
        expect(section.description).to eq("Existing description")
        expect(section.country).to eq("US")
        expect(section.keywords).to eq("gaming reviews")
      end
    end

    it "returns the cached banner URL string from the update response" do
      result = described_class.new(connection).upload_banner(channel, fake_io)
      expect(result).to eq("https://yt3.googleusercontent.com/abc/banner.jpg")
    end

    it "falls back to the insert token when update response lacks banner_external_url" do
      no_url_response = OpenStruct.new(
        id: "UCabcabcabcabcabcabcabcA",
        snippet: OpenStruct.new(title: "Existing Title"),
        statistics: OpenStruct.new(subscriber_count: "1"),
        branding_settings: OpenStruct.new(
          channel: OpenStruct.new(title: "Existing Title"),
          image: OpenStruct.new(banner_external_url: nil)
        )
      )
      allow(svc).to receive(:update_channel).and_return(no_url_response)

      result = described_class.new(connection).upload_banner(channel, fake_io)
      expect(result).to eq("https://upload.youtube/banner-token-123")
    end

    it "writes three audit rows (insert, list, update) — one per logical call" do
      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to change { YoutubeApiCall.unscoped.count }.by(3)

      endpoints = YoutubeApiCall.unscoped.last(3).map(&:endpoint)
      expect(endpoints).to contain_exactly("channelBanners.insert", "channels.list", "channels.update")

      insert_row = YoutubeApiCall.unscoped.where(endpoint: "channelBanners.insert").last
      expect(insert_row.units).to eq(50)
      expect(insert_row.outcome).to eq("success")
      expect(insert_row.youtube_connection_id).to eq(connection.id)

      update_row = YoutubeApiCall.unscoped.where(endpoint: "channels.update").last
      expect(update_row.units).to eq(50)
      expect(update_row.outcome).to eq("success")
    end
  end

  describe "argument validation" do
    before { stub_data_service(svc) }

    it "raises ArgumentError when channel is nil" do
      expect {
        described_class.new(connection).upload_banner(nil, fake_io)
      }.to raise_error(ArgumentError, /channel required/)
    end

    it "raises ArgumentError when io is nil" do
      expect {
        described_class.new(connection).upload_banner(channel, nil)
      }.to raise_error(ArgumentError, /io required/)
    end

    it "raises ArgumentError when channel.channel_url has no UC id" do
      bad_channel = build_stubbed(:channel, channel_url: "https://example.test/no-id")
      expect {
        described_class.new(connection).upload_banner(bad_channel, fake_io)
      }.to raise_error(ArgumentError, /channel id/)
    end
  end

  describe "sad paths" do
    before { stub_data_service(svc) }

    it "raises QuotaExhaustedError when pre-call budget refuses" do
      allow(Youtube::Quota).to receive(:budget_remaining).and_return(0)
      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises QuotaExhaustedError when YouTube returns 403 quotaExceeded on insert" do
      err = Google::Apis::ClientError.new(
        "Quota exceeded",
        status_code: 403,
        body: '{"error":{"errors":[{"reason":"quotaExceeded"}]}}'
      )
      allow(svc).to receive(:insert_channel_banner).and_raise(err)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::QuotaExhaustedError)
    end

    it "raises TransientError after MAX_5XX_ATTEMPTS 5xx responses on insert" do
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("Internal", status_code: 500, body: "{}")
      allow(svc).to receive(:insert_channel_banner).and_raise(err)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::TransientError)
    end

    it "raises NeedsReauthError on 401 after refresh" do
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new(
        "Unauthorized", status_code: 401, body: '{"error":"invalid_token"}'
      )
      allow(svc).to receive(:insert_channel_banner).and_raise(err)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::NeedsReauthError)
      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "raises PermanentError when YouTube rejects dimensions (400 imageDimensionsInvalid)" do
      err = Google::Apis::ClientError.new(
        "Bad request",
        status_code: 400,
        body: '{"error":{"errors":[{"reason":"imageDimensionsInvalid"}],"code":400,"message":"Image dimensions invalid"}}'
      )
      allow(svc).to receive(:insert_channel_banner).and_raise(err)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::PermanentError, /400/)
    end

    it "raises TransientError on network timeout during insert" do
      allow(svc).to receive(:insert_channel_banner).and_raise(Net::ReadTimeout.new("read timeout"))

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::TransientError)
    end

    it "raises PermanentError when channelBanners.insert returns an empty url" do
      allow(svc).to receive(:insert_channel_banner).and_return(
        OpenStruct.new(kind: "youtube#channelBannerResource", url: "")
      )

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::PermanentError, /no banner url/)
    end

    it "stops after Step 1 failure — does NOT fire channels.update" do
      err = Google::Apis::ClientError.new(
        "Bad request",
        status_code: 400,
        body: '{"error":{"errors":[{"reason":"imageDimensionsInvalid"}]}}'
      )
      allow(svc).to receive(:insert_channel_banner).and_raise(err)
      allow(svc).to receive(:list_channels)
      allow(svc).to receive(:update_channel)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::PermanentError)

      expect(svc).not_to have_received(:list_channels)
      expect(svc).not_to have_received(:update_channel)
    end

    it "surfaces a Step 2 failure (channels.update transient 5xx) and rolls back the insert audit-wise" do
      allow_any_instance_of(described_class).to receive(:sleep)
      allow(svc).to receive(:insert_channel_banner).and_return(insert_banner_response)
      allow(svc).to receive(:list_channels).and_return(branding_read_response)
      err = Google::Apis::ServerError.new("Internal", status_code: 500, body: "{}")
      allow(svc).to receive(:update_channel).and_raise(err)

      expect {
        described_class.new(connection).upload_banner(channel, fake_io)
      }.to raise_error(Youtube::TransientError)

      # The insert audit row was written (Step 1 succeeded); the
      # update audit row records the server_error outcome.
      update_rows = YoutubeApiCall.unscoped.where(endpoint: "channels.update")
      expect(update_rows.last.outcome).to eq("server_error")
    end
  end
end
