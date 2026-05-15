require "rails_helper"

RSpec.describe Auth::AttemptLogger do
  let(:user) { create(:user) }

  def fake_request(remote_ip: "1.2.3.4", user_agent: "AgentSpec/1.0", params: {})
    request = ActionDispatch::TestRequest.create
    request.env["REMOTE_ADDR"] = remote_ip
    request.env["HTTP_USER_AGENT"] = user_agent
    # The composer reads `request.params["fp_screen"]` / `["fp_locale"]`.
    request.env["action_dispatch.request.parameters"] = params.stringify_keys
    request
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe ".call" do
    describe "happy path" do
      it "writes a success row with the right fingerprint and ip_prefix" do
        row = described_class.call(
          request: fake_request,
          result: :success,
          reason: :trusted_location_success,
          user: user,
          username: user.username
        )

        expect(row).to be_persisted
        expect(row.result).to eq("success")
        expect(row.reason).to eq("trusted_location_success")
        expect(row.user_id).to eq(user.id)
        expect(row.email_attempted).to eq(user.username.to_s)
        expect(row.ip.to_s).to eq("1.2.3.4")
        expect(row.ip_prefix).to eq("1.2.3.0/24")
        expect(row.fingerprint_hash.length).to eq(64)
        expect(row.user_agent).to eq("AgentSpec/1.0")
      end

      it "no job is enqueued when geo enricher did not defer" do
        Auth::GeoEnricher.reset_deferred!
        allow(Auth::GeoEnricher).to receive(:call).and_return(city: "x", region: "y", country: "ZZ")
        allow(Auth::GeoEnricher).to receive(:deferred?).and_return(false)

        expect {
          described_class.call(
            request: fake_request,
            result: :success,
            reason: :trusted_location_success,
            user: user,
            username: user.username
          )
        }.not_to change(LoginAttemptGeoEnrichJob.jobs, :size)
      end
    end

    describe "sad: wrong password" do
      it "writes a failed row with reason: wrong_password and user_id" do
        row = described_class.call(
          request: fake_request,
          result: :failed,
          reason: :wrong_password,
          user: user,
          username: user.username
        )
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("wrong_password")
        expect(row.user_id).to eq(user.id)
      end
    end

    describe "sad: unknown username" do
      it "writes a failed row with reason: unknown_account and nil user_id" do
        row = described_class.call(
          request: fake_request,
          result: :failed,
          reason: :unknown_account,
          username: "nobody_user"
        )
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("unknown_account")
        expect(row.user_id).to be_nil
        expect(row.email_attempted).to eq("nobody_user")
      end
    end

    describe "blocked-pair short-circuit" do
      let(:request) { fake_request(remote_ip: "5.5.5.5") }
      let(:fingerprint) do
        Auth::FingerprintComposer.call(
          request: request,
          screen_hint: nil,
          locale_hint: nil
        )
      end

      before do
        create(
          :blocked_location,
          fingerprint_hash: fingerprint,
          ip_prefix: "5.5.5.0/24",
          blocked_by_user: user
        )
      end

      it "rewrites a success result to blocked when the pair is on the list" do
        row = described_class.call(
          request: request,
          result: :success,
          reason: :trusted_location_success,
          user: user,
          username: user.username
        )
        expect(row.result).to eq("blocked")
        expect(row.reason).to eq("blocked_pair")
      end

      it "bumps BlockedLocation#attempt_count + stamps last_attempt_at" do
        bl = BlockedLocation.find_by(fingerprint_hash: fingerprint, ip_prefix: "5.5.5.0/24")
        expect {
          described_class.call(
            request: request,
            result: :failed,
            reason: :wrong_password,
            username: "x_y_user"
          )
        }.to change { bl.reload.attempt_count }.by(1)
        expect(bl.last_attempt_at).to be_within(2.seconds).of(Time.current)
      end

      it "does not bump on an explicitly-blocked caller path (already blocked)" do
        bl = BlockedLocation.find_by(fingerprint_hash: fingerprint, ip_prefix: "5.5.5.0/24")
        expect {
          described_class.call(
            request: request,
            result: :blocked,
            reason: :blocked_pair,
            username: "x_y_user"
          )
        }.not_to change { bl.reload.attempt_count }
      end
    end

    describe "edge: geo enricher missed → async job enqueued" do
      before do
        allow(Auth::GeoEnricher).to receive(:call).and_return(city: nil, region: nil, country: nil)
        allow(Auth::GeoEnricher).to receive(:deferred?).and_return(true)
      end

      it "enqueues LoginAttemptGeoEnrichJob with the new row id" do
        expect {
          described_class.call(
            request: fake_request,
            result: :failed,
            reason: :wrong_password,
            username: "x_y_user"
          )
        }.to change(LoginAttemptGeoEnrichJob.jobs, :size).by(1)
      end
    end

    describe "edge: rate-limited" do
      it "writes a failed row with reason: rate_limited" do
        row = described_class.call(
          request: fake_request,
          result: :failed,
          reason: :rate_limited,
          username: "x_y_user"
        )
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("rate_limited")
      end
    end

    describe "edge: malformed remote_ip falls back to 0.0.0.0/24" do
      it "still writes a row with a safe prefix" do
        request = fake_request(remote_ip: "")
        row = described_class.call(
          request: request,
          result: :failed,
          reason: :wrong_password,
          username: "x_y_user"
        )
        expect(row.ip_prefix).to eq("0.0.0.0/24")
      end
    end

    describe "flaw: never logs the raw password" do
      it "does not surface the password in the row" do
        row = described_class.call(
          request: fake_request(params: { "password" => "shh-secret-XX" }),
          result: :failed,
          reason: :wrong_password,
          username: "x_y_user"
        )
        expect(row.attributes.values.map(&:to_s)).not_to include(a_string_matching(/shh-secret-XX/))
      end
    end

    describe "validation: result vocabulary" do
      it "raises ArgumentError for an unknown result symbol" do
        expect {
          described_class.call(
            request: fake_request,
            result: :exploded,
            reason: :wrong_password
          )
        }.to raise_error(ArgumentError, /result must be one of/)
      end
    end
  end
end
