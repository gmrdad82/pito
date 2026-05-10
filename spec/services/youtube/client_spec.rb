require "rails_helper"
require "ostruct"

# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# `Youtube::Client.new(connection)` accepts a `YoutubeConnection`; the
# audit row's column flipped to `youtube_connection_id`.
#
# Test fixture strategy (decision 7.16): WebMock stubs against
# canned response shapes — VCR cassettes against real traffic are
# deferred to a follow-up cassette-recording session.
#
# These specs stub the underlying Google::Apis::YoutubeV3::YouTubeService
# methods directly via `allow(...).to receive(...)`. The behavior
# under test is the client's wrapper logic (quota check, retry,
# refresh, audit-row write, response normalization), not the
# Google gem's HTTP serialization.
RSpec.describe Youtube::Client do
  let(:connection) { create(:youtube_connection) }

  # Stub the data service so we control its return value or
  # raise behavior without hitting the network.
  #
  # Phase 15 F2 — `Youtube::ServiceFactory` writes timeout values to
  # `client_options` on every newly built service. The double has to
  # expose a settable struct so the factory's real construction path
  # runs without explicit factory mocking.
  def stub_data_service(svc_double)
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc_double)
    allow(svc_double).to receive(:client_options).and_return(
      Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil)
    )
  end

  describe "#channels_list (happy path)" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(
          items: [
            OpenStruct.new(
              id: "UCabc",
              snippet: OpenStruct.new(title: "Main Channel", description: "desc"),
              statistics: OpenStruct.new(subscriber_count: 1234, view_count: 5_678_901)
            )
          ],
          next_page_token: nil
        )
      )
      stub_data_service(svc)
    end

    it "returns a pito-shape Hash with snake_case keys" do
      result = described_class.new(connection).channels_list(mine: true)
      expect(result).to be_a(Hash)
      expect(result.keys).to include(:items, :next_page_token)
      first = result[:items].first
      expect(first[:id]).to eq("UCabc")
      expect(first[:snippet][:title]).to eq("Main Channel")
      expect(first[:statistics][:subscriber_count]).to eq(1234)
    end

    it "writes one audit row with outcome=success and youtube_connection_id set" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("channels.list")
      expect(row.outcome).to eq("success")
      expect(row.client_kind).to eq("oauth")
      expect(row.units).to eq(1)
      expect(row.youtube_connection_id).to eq(connection.id)
    end
  end

  describe "pre-call quota refusal" do
    before do
      allow(Youtube::Quota).to receive(:budget_remaining).and_return(0)
    end

    it "raises QuotaExhaustedError, audits with outcome=quota_exceeded and http_status nil" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to raise_error(Youtube::QuotaExhaustedError)

      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("quota_exceeded")
      expect(row.http_status).to be_nil
    end
  end

  describe "expired token: refresh + retry" do
    let(:connection) { create(:youtube_connection, :expired) }
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      GoogleStubs.stub_refresh_success(access_token: "ya29.fresh", expires_in: 3600)
      allow(svc).to receive(:authorization=)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [], next_page_token: nil)
      )
      stub_data_service(svc)
    end

    it "refreshes the token before issuing the call" do
      described_class.new(connection).channels_list(mine: true)
      expect(connection.reload.last_refreshed_at).to be_within(5.seconds).of(Time.current)
      expect(connection.reload.access_token).to eq("ya29.fresh")
    end

    it "writes exactly one audit row (one row per logical call)" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)
    end
  end

  describe "401 mid-call → refresh + retry → 401 again → NeedsReauthError" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      GoogleStubs.stub_refresh_success
      allow(svc).to receive(:authorization=)

      # First call: 401. Refresh runs, then second call: 401 again.
      err = Google::Apis::AuthorizationError.new("Unauthorized", status_code: 401, body: '{"error":"invalid_token"}')
      allow(svc).to receive(:list_channels).and_raise(err)
      stub_data_service(svc)
    end

    it "flips needs_reauth=true and raises NeedsReauthError" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to raise_error(Youtube::NeedsReauthError)
      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "audits a single row with outcome=auth_failed" do
      expect {
        described_class.new(connection).channels_list(mine: true) rescue nil
      }.to change { YoutubeApiCall.unscoped.where(outcome: "auth_failed").count }.by(1)
    end
  end

  describe "5xx retry-and-recover" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      stub_data_service(svc)
      # Sleep is a side-effect of backoff; stub for fast tests.
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("oops", status_code: 503, body: "")
      call_count = 0
      allow(svc).to receive(:list_channels) do
        call_count += 1
        raise err if call_count < 3
        OpenStruct.new(items: [], next_page_token: nil)
      end
    end

    it "retries up to 3 times and audits a single success row" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      expect(YoutubeApiCall.unscoped.last.outcome).to eq("success")
    end
  end

  describe "5xx exhausted → TransientError" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      stub_data_service(svc)
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("oops", status_code: 503, body: "")
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "audits server_error after the retries and raises TransientError" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to raise_error(Youtube::TransientError)

      row = YoutubeApiCall.unscoped.where(outcome: "server_error").last
      expect(row).not_to be_nil
    end
  end

  describe "403 quotaExceeded" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      stub_data_service(svc)

      err = Google::Apis::ClientError.new(
        "Forbidden",
        status_code: 403,
        body: '{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}'
      )
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises QuotaExhaustedError without retry, audits outcome=quota_exceeded" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to raise_error(Youtube::QuotaExhaustedError)

      expect(YoutubeApiCall.unscoped.last.outcome).to eq("quota_exceeded")
    end
  end

  # Bug-fix regression suite — Google returns 403 PERMISSION_DENIED with
  # "Request had insufficient authentication scopes." when the stored
  # token's scope set no longer matches what the called endpoint
  # requires (the consent screen gained a scope after the connection
  # was minted). Pito classifies this as needs-reauth, not permanent,
  # so the manage page can surface [reconnect] instead of bubbling a
  # 500 to the Rails error page.
  describe "403 insufficient authentication scopes" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      stub_data_service(svc)
    end

    context "exact-message body shape from Google" do
      before do
        body = {
          error: {
            code: 403,
            message: "Request had insufficient authentication scopes.",
            errors: [ { reason: "insufficientPermissions",
                        message: "Insufficient Permission" } ],
            status: "PERMISSION_DENIED"
          }
        }.to_json
        err = Google::Apis::ClientError.new(
          "Request had insufficient authentication scopes.",
          status_code: 403,
          body: body
        )
        allow(svc).to receive(:list_channels).and_raise(err)
      end

      it "raises NeedsReauthError (not PermanentError)" do
        expect {
          described_class.new(connection).channels_list(mine: true)
        }.to raise_error(Youtube::NeedsReauthError, /insufficient authentication scopes/i)
      end

      it "flips needs_reauth=true on the connection" do
        expect {
          described_class.new(connection).channels_list(mine: true) rescue nil
        }.to change { connection.reload.needs_reauth? }.from(false).to(true)
      end

      it "audits one row with outcome=auth_failed and http_status=403" do
        expect {
          described_class.new(connection).channels_list(mine: true) rescue nil
        }.to change { YoutubeApiCall.unscoped.count }.by(1)

        row = YoutubeApiCall.unscoped.last
        expect(row.outcome).to eq("auth_failed")
        expect(row.http_status).to eq(403)
      end
    end

    context "case-insensitive match" do
      before do
        err = Google::Apis::ClientError.new(
          "PERMISSION_DENIED",
          status_code: 403,
          body: '{"error":{"code":403,"message":"Request had INSUFFICIENT AUTHENTICATION SCOPES."}}'
        )
        allow(svc).to receive(:list_channels).and_raise(err)
      end

      it "still raises NeedsReauthError regardless of casing" do
        expect {
          described_class.new(connection).channels_list(mine: true)
        }.to raise_error(Youtube::NeedsReauthError)
      end
    end

    context "match in the exception message (body absent)" do
      before do
        err = Google::Apis::ClientError.new(
          "Request had insufficient authentication scopes.",
          status_code: 403,
          body: ""
        )
        allow(svc).to receive(:list_channels).and_raise(err)
      end

      it "raises NeedsReauthError when only the message carries the signal" do
        expect {
          described_class.new(connection).channels_list(mine: true)
        }.to raise_error(Youtube::NeedsReauthError)
      end
    end
  end

  # Counter-test — a generic 403 (not quotaExceeded, not insufficient
  # scopes) must continue to raise PermanentError. Guards against
  # over-broadening the needs-reauth carve-out.
  describe "403 other (non-quota, non-scopes)" do
    let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    before do
      allow(svc).to receive(:authorization=)
      stub_data_service(svc)

      err = Google::Apis::ClientError.new(
        "Forbidden",
        status_code: 403,
        body: '{"error":{"code":403,"message":"The caller does not have permission.","errors":[{"reason":"forbidden"}]}}'
      )
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises PermanentError, audits outcome=client_error" do
      expect {
        described_class.new(connection).channels_list(mine: true)
      }.to raise_error(Youtube::PermanentError, /client error 403/)

      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("client_error")
      expect(row.http_status).to eq(403)
    end

    it "does NOT flip needs_reauth=true" do
      expect {
        described_class.new(connection).channels_list(mine: true) rescue nil
      }.not_to change { connection.reload.needs_reauth? }
    end
  end
end
