require "rails_helper"
require_relative "../../../app/mcp/tools/totp_status"

# Phase 25 — 01e. `totp_status` MCP read tool.
RSpec.describe Mcp::Tools::TotpStatus do
  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    it "reports totp_enabled: 'no' for an unenrolled user" do
      data = parse(call_tool)
      expect(data["totp_enabled"]).to eq("no")
      expect(data["unused_backup_codes"]).to eq(0)
    end

    it "reports totp_enabled: 'yes' + enabled_at + unused count for an enrolled user" do
      user = Current.user
      user.update!(
        totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
        totp_enabled_at: 1.hour.ago
      )
      3.times { |i| user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("CODE#{i}234")) }

      data = parse(call_tool)
      expect(data["totp_enabled"]).to eq("yes")
      expect(data["unused_backup_codes"]).to eq(3)
      expect(data["totp_enabled_at"]).to be_present
    end

    it "carries the documented keys" do
      data = parse(call_tool)
      %w[user_id email totp_enabled totp_enabled_at totp_disabled_at
         unused_backup_codes used_backup_codes].each do |k|
        expect(data.keys).to include(k), "missing key #{k}"
      end
    end

    it "yes/no Boolean boundary — totp_enabled is always a yes/no string" do
      data = parse(call_tool)
      expect(%w[yes no]).to include(data["totp_enabled"])
    end

    it "counts stay numeric per the hard rule (yes/no is for Booleans only)" do
      data = parse(call_tool)
      expect(data["unused_backup_codes"]).to be_a(Integer)
      expect(data["used_backup_codes"]).to be_a(Integer)
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-totp-status",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
