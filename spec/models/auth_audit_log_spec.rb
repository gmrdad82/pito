require "rails_helper"

# AuthAuditLog model. Post-Phase-25 rollback: the location-tied
# action vocabulary (approve / block / unblock / purge) is gone; the
# active allowlist covers TOTP lifecycle + Voyage credential writes +
# password reset. The integer enum values stay RESERVED (`0..3`,
# plus `7` for the retired `youtube_credentials_updated`).
RSpec.describe AuthAuditLog do
  describe "validations" do
    it "requires acting_user_id" do
      row = described_class.new(
        source_surface: :web,
        action: :totp_enroll,
        target_type: "User",
        target_id: 1
      )
      expect(row).not_to be_valid
      expect(row.errors[:acting_user_id]).to be_present
    end

    it "requires source_surface" do
      row = build(:auth_audit_log, source_surface: nil)
      expect(row).not_to be_valid
      expect(row.errors[:source_surface]).to be_present
    end

    it "requires action" do
      row = build(:auth_audit_log, action: nil)
      expect(row).not_to be_valid
      expect(row.errors[:action]).to be_present
    end

    it "requires target_type" do
      row = build(:auth_audit_log, target_type: nil)
      expect(row).not_to be_valid
      expect(row.errors[:target_type]).to be_present
    end

    it "requires target_id" do
      row = build(:auth_audit_log, target_id: nil)
      expect(row).not_to be_valid
      expect(row.errors[:target_id]).to be_present
    end

    it "persists when all required attrs are present" do
      row = build(:auth_audit_log)
      expect(row).to be_valid
      expect(row.save).to be true
    end
  end

  describe "source_surface enum" do
    %i[web tui mcp].each do |surface|
      it "accepts #{surface}" do
        row = build_stubbed(:auth_audit_log, source_surface: surface)
        expect(row.source_surface).to eq(surface.to_s)
      end
    end

    it "raises ArgumentError on unknown surface" do
      expect {
        described_class.new(source_surface: :sms)
      }.to raise_error(ArgumentError)
    end

    it "exposes source_<value>? predicates" do
      row = build_stubbed(:auth_audit_log, source_surface: :tui)
      expect(row.source_tui?).to be true
      expect(row.source_web?).to be false
    end
  end

  describe "action enum" do
    %i[totp_enroll totp_disable backup_code_regenerate
       voyage_credentials_updated password_reset].each do |action|
      it "accepts #{action}" do
        row = build_stubbed(:auth_audit_log, action: action)
        expect(row.action).to eq(action.to_s)
      end
    end

    it "raises ArgumentError on the retired location-tied actions" do
      %i[approve block unblock purge].each do |action|
        expect {
          described_class.new(action: action)
        }.to raise_error(ArgumentError)
      end
    end

    it "raises ArgumentError on unknown action" do
      expect {
        described_class.new(action: :destroy_universe)
      }.to raise_error(ArgumentError)
    end

    it "exposes action_<value>? predicates" do
      row = build_stubbed(:auth_audit_log, action: :totp_disable)
      expect(row.action_totp_disable?).to be true
      expect(row.action_totp_enroll?).to be false
    end
  end

  describe "associations" do
    it "belongs_to :acting_user (required)" do
      row = described_class.reflect_on_association(:acting_user)
      expect(row.macro).to eq(:belongs_to)
      expect(row.options[:class_name]).to eq("User")
    end
  end

  describe "scopes" do
    let!(:user_a) { create(:user) }
    let!(:user_b) { create(:user) }
    let!(:row1) {
      create(:auth_audit_log, acting_user: user_a, action: :totp_enroll,
                              target_type: "User", target_id: user_a.id)
    }
    let!(:row2) {
      create(:auth_audit_log, acting_user: user_b, action: :totp_disable,
                              target_type: "User", target_id: user_a.id)
    }
    let!(:row3) {
      create(:auth_audit_log, acting_user: user_a, action: :backup_code_regenerate,
                              target_type: "User", target_id: 999)
    }

    it ".recent orders by created_at desc" do
      rows = described_class.recent
      expect(rows.first.created_at).to be >= rows.last.created_at
    end

    it ".for_target filters by (type, id)" do
      rows = described_class.for_target("User", user_a.id)
      expect(rows.pluck(:id)).to contain_exactly(row1.id, row2.id)
    end

    it ".for_acting_user filters by user" do
      rows = described_class.for_acting_user(user_a)
      expect(rows.pluck(:id)).to contain_exactly(row1.id, row3.id)
    end

    it ".for_acting_user returns none when user is nil" do
      expect(described_class.for_acting_user(nil)).to eq([])
    end

    it ".since filters by created_at" do
      row3.update_columns(created_at: 2.days.ago)
      expect(described_class.since(1.day.ago).pluck(:id))
        .to contain_exactly(row1.id, row2.id)
    end
  end

  describe "metadata jsonb" do
    it "round-trips arbitrary string-keyed data" do
      row = create(:auth_audit_log, metadata: { "session_id" => 42, "note" => "ok" })
      reloaded = described_class.find(row.id)
      expect(reloaded.metadata).to eq("session_id" => 42, "note" => "ok")
    end

    it "defaults to an empty hash" do
      row = build_stubbed(:auth_audit_log)
      expect(row.metadata).to eq({})
    end
  end
end
