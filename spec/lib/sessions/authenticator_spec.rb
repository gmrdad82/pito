require "rails_helper"

RSpec.describe Sessions::Authenticator do
  let(:user) { create(:user) }

  # Build a real `ActionDispatch::TestRequest` (which has the application's
  # key generator wired) and put a signed cookie on it. Round-trip the
  # cookie through `Set-Cookie` header parsing so the read path is
  # exercised end-to-end exactly as in production.
  def request_carrying(plaintext)
    seed = ActionDispatch::TestRequest.create
    jar = ActionDispatch::Cookies::CookieJar.build(seed, {})
    jar.signed[Sessions::Authenticator::COOKIE_NAME] = plaintext
    raw_value = jar[Sessions::Authenticator::COOKIE_NAME.to_s]

    new_env = Rack::MockRequest.env_for("/")
    new_req = ActionDispatch::TestRequest.create(new_env)
    new_req.cookie_jar[Sessions::Authenticator::COOKIE_NAME.to_s] = raw_value
    new_req
  end

  it "returns missing-cookie failure when the cookie is absent" do
    req = ActionDispatch::TestRequest.create
    result = described_class.call(req)
    expect(result).to be_failure
    expect(result.reason).to eq(:missing)
  end

  it "returns success and the row for a valid cookie" do
    record, plaintext = Session.create_for!(user: user, ip: "127.0.0.1", user_agent: "ua", remember: false)
    result = described_class.call(request_carrying(plaintext))

    expect(result).to be_success
    expect(result.session).to eq(record)
  end

  it "returns unknown_token when the digest does not match any row" do
    result = described_class.call(request_carrying("not-a-valid-token"))
    expect(result).to be_failure
    expect(result.reason).to eq(:unknown_token)
  end

  it "returns revoked when the row is revoked" do
    record, plaintext = Session.create_for!(user: user, ip: "127.0.0.1", user_agent: "ua", remember: false)
    record.revoke!

    result = described_class.call(request_carrying(plaintext))
    expect(result).to be_failure
    expect(result.reason).to eq(:revoked)
    expect(result.session).to eq(record)
  end

  it "returns auth_misconfigured when the pepper cannot resolve" do
    allow(Pito::TokenDigest).to receive(:call).and_raise(Api::AuthConfigurationMissing)

    result = described_class.call(request_carrying("anything"))
    expect(result.reason).to eq(:auth_misconfigured)
  end
end
