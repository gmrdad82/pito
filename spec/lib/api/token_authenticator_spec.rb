require "rails_helper"

RSpec.describe Api::TokenAuthenticator do
  let(:tenant) { Current.tenant || create(:tenant).tap { |t| Current.tenant = t } }
  let(:user)   { Current.user   || create(:user, tenant: tenant).tap { |u| Current.user = u } }

  def env_for(authorization: nil, path: "/mcp", method: "POST")
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO"      => path,
      "REMOTE_ADDR"    => "127.0.0.1"
    }
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    env
  end

  describe ".call" do
    it "returns failure with reason 'missing_token' when no Authorization header is present" do
      result = described_class.call(env_for)

      expect(result).to be_failure
      expect(result.failure_reason).to eq("missing_token")
    end

    it "returns failure with reason 'missing_token' when Authorization header is empty Bearer" do
      result = described_class.call(env_for(authorization: "Bearer "))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("missing_token")
    end

    it "returns failure with reason 'missing_token' when Authorization is not a Bearer scheme" do
      result = described_class.call(env_for(authorization: "Basic abc123"))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("missing_token")
    end

    it "returns failure with reason 'invalid_token' when the token is unknown" do
      result = described_class.call(env_for(authorization: "Bearer not-a-real-token"))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("invalid_token")
    end

    it "returns failure with reason 'revoked_token' when the token is revoked" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "rv", scopes: [ Scopes::DEV_READ ]
      )
      record.revoke!

      result = described_class.call(env_for(authorization: "Bearer #{plaintext}"))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("revoked_token")
    end

    it "returns failure with reason 'expired_token' when the token has expired" do
      _record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "ex", scopes: [ Scopes::DEV_READ ],
        expires_at: 1.minute.ago
      )

      result = described_class.call(env_for(authorization: "Bearer #{plaintext}"))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("expired_token")
    end

    it "returns success and the token on a valid, usable Bearer header" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "ok", scopes: [ Scopes::DEV_READ ]
      )

      result = described_class.call(env_for(authorization: "Bearer #{plaintext}"))

      expect(result).to be_success
      expect(result.token).to eq(record)
    end

    it "updates last_used_at on the token on success" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "u", scopes: [ Scopes::DEV_READ ]
      )

      expect { described_class.call(env_for(authorization: "Bearer #{plaintext}")) }
        .to change { record.reload.last_used_at }.from(nil)
    end

    it "sets env['pito.auth_failed'] = true on every failure path" do
      env = env_for # missing
      described_class.call(env)
      expect(env["pito.auth_failed"]).to be true

      env2 = env_for(authorization: "Bearer wrong")
      described_class.call(env2)
      expect(env2["pito.auth_failed"]).to be true
    end

    it "does not set env['pito.auth_failed'] on success" do
      _record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "success-no-flag",
        scopes: [ Scopes::DEV_READ ]
      )

      env = env_for(authorization: "Bearer #{plaintext}")
      described_class.call(env)
      expect(env["pito.auth_failed"]).to be_nil
    end

    it "returns auth_misconfigured when the pepper credential is missing" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)

      result = described_class.call(env_for(authorization: "Bearer something"))

      expect(result).to be_failure
      expect(result.failure_reason).to eq("auth_misconfigured")
    end

    it "writes a JSON line to the audit log on every code path" do
      io = StringIO.new
      stub_const("AUTH_AUDIT_LOGGER", Logger.new(io).tap do |l|
        l.formatter = ->(_, _, _, msg) { "#{msg}\n" }
      end)

      _record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "audit",
        scopes: [ Scopes::DEV_READ ]
      )

      described_class.call(env_for(authorization: "Bearer #{plaintext}"))
      described_class.call(env_for(authorization: "Bearer bad"))

      lines = io.string.lines.map { |l| JSON.parse(l) }
      expect(lines.size).to eq(2)

      expect(lines[0]["event"]).to eq("auth.success")
      expect(lines[0]["result"]).to eq("ok")
      expect(lines[0]["ip"]).to eq("127.0.0.1")
      expect(lines[0]["route"]).to eq("POST /mcp")

      expect(lines[1]["event"]).to eq("auth.invalid_token")
      expect(lines[1]["result"]).to eq("invalid_token")
    end
  end

  describe "Result#to_rack_response" do
    it "renders a 401 JSON triplet for invalid_token" do
      result = described_class::Result.new(failure_reason: "invalid_token")
      status, headers, body = result.to_rack_response

      expect(status).to eq(401)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(JSON.parse(body.first)).to eq("error" => "invalid_token")
    end

    it "renders a 500 JSON triplet for auth_misconfigured" do
      result = described_class::Result.new(failure_reason: "auth_misconfigured")
      status, _headers, body = result.to_rack_response

      expect(status).to eq(500)
      expect(JSON.parse(body.first)).to eq("error" => "auth_misconfigured")
    end

    it "renders a 429 JSON triplet for rate_limited" do
      result = described_class::Result.new(failure_reason: "rate_limited")
      status, _headers, body = result.to_rack_response

      expect(status).to eq(429)
      expect(JSON.parse(body.first)).to eq("error" => "rate_limited")
    end
  end
end
