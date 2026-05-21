require "rails_helper"

# Post-Phase-25 rollback. SessionActivator's sole responsibility is
# minting a fresh active Session row + returning the plaintext for the
# cookie. The trusted-location upsert and LoginAttempt write are gone
# along with the new-location approval surface.
RSpec.describe Pito::Auth::SessionActivator do
  let(:user) { create(:user) }

  def fake_request(remote_ip: "10.60.0.2", user_agent: "AgentActivator/1.0")
    request = ActionDispatch::TestRequest.create
    request.env["REMOTE_ADDR"] = remote_ip
    request.env["HTTP_USER_AGENT"] = user_agent
    request
  end

  describe ".call (happy)" do
    it "creates a fresh :active session row" do
      record, _plaintext = described_class.call(user: user, request: fake_request)
      expect(record).to be_persisted
      expect(record.state_active?).to be true
    end

    it "returns [record, plaintext] tuple for cookie minting" do
      record, plaintext = described_class.call(user: user, request: fake_request)
      expect(record).to be_persisted
      expect(plaintext).to be_a(String)
      expect(plaintext.length).to be > 16
    end

    it "captures the remote_ip + user_agent on the row" do
      record, _ = described_class.call(
        user: user,
        request: fake_request(remote_ip: "203.0.113.5", user_agent: "TestAgent/2.0")
      )
      expect(record.ip).to eq("203.0.113.5")
      expect(record.user_agent).to eq("TestAgent/2.0")
    end

    it "tolerates a nil request (mints with placeholder ip / blank user_agent)" do
      record, plaintext = described_class.call(user: user, request: nil)
      expect(record).to be_persisted
      expect(plaintext).to be_present
      expect(record.ip).to eq("0.0.0.0")
    end
  end

  describe ".call (sad)" do
    it "raises ArgumentError on missing user" do
      expect {
        described_class.call(user: nil, request: fake_request)
      }.to raise_error(ArgumentError, /user required/)
    end
  end
end
