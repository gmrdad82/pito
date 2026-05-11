require "rails_helper"

RSpec.describe LoginAttempt, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations" do
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:notification).optional }
    it { is_expected.to belong_to(:approved_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:result) }
    it { is_expected.to validate_presence_of(:reason) }
    it { is_expected.to validate_presence_of(:ip) }
    it { is_expected.to validate_presence_of(:ip_prefix) }
    it { is_expected.to validate_presence_of(:fingerprint_hash) }
    it { is_expected.to validate_length_of(:fingerprint_hash).is_equal_to(64) }

    it "rejects mismatched ip / ip_prefix families" do
      row = build(:login_attempt, ip: "1.2.3.4", ip_prefix: "2001:db8::/64")
      expect(row).not_to be_valid
      expect(row.errors[:ip_prefix]).to include("family must match ip")
    end

    it "rejects a malformed ip_prefix" do
      row = build(:login_attempt, ip: "1.2.3.4", ip_prefix: "garbage")
      expect(row).not_to be_valid
      expect(row.errors[:ip_prefix]).to include("is not a valid CIDR")
    end

    it "accepts an IPv6 ip paired with a /64 prefix" do
      row = build(:login_attempt, ip: "2001:db8::1", ip_prefix: "2001:db8::/64")
      expect(row).to be_valid
    end
  end

  describe "enums" do
    it "exposes the LD-1 result vocabulary" do
      expect(described_class.results.keys).to contain_exactly(
        "success", "failed", "pending_approval", "blocked", "rate_limited"
      )
    end

    it "exposes the LD-1 reason vocabulary verbatim (15 reasons)" do
      expect(described_class.reasons.size).to eq(15)
      %w[wrong_password unknown_account new_location_pending
         new_location_2fa_passed trusted_location_success blocked_pair
         rate_limited twofa_failed approved_from_web approved_from_tui
         approved_from_mcp blocked_from_web blocked_from_tui
         blocked_from_mcp pending_expired].each do |reason|
        expect(described_class.reasons.key?(reason)).to be(true), "missing reason #{reason}"
      end
    end
  end

  describe "scopes" do
    let!(:succ) { create(:login_attempt, :success, :with_geo) }
    let!(:fail_a) { travel_to(1.hour.ago) { create(:login_attempt) } }
    let!(:fail_b) { create(:login_attempt) }
    let!(:blocked) { create(:login_attempt, :blocked) }

    it "recent orders by created_at desc" do
      expect(described_class.recent.first).to eq(blocked)
      expect(described_class.recent.last).to eq(fail_a)
    end

    it "failed returns only failed rows" do
      ids = described_class.failed.pluck(:id)
      expect(ids).to contain_exactly(fail_a.id, fail_b.id)
    end

    it "succeeded returns only success rows" do
      expect(described_class.succeeded.pluck(:id)).to eq([ succ.id ])
    end

    it "blocked_results returns only blocked rows" do
      expect(described_class.blocked_results.pluck(:id)).to eq([ blocked.id ])
    end

    it "for_user scopes by user_id" do
      expect(described_class.for_user(succ.user).pluck(:id)).to eq([ succ.id ])
    end

    it "for_fingerprint scopes by fingerprint_hash" do
      expect(described_class.for_fingerprint(succ.fingerprint_hash)).to contain_exactly(succ)
    end

    it "since filters by created_at" do
      expect(described_class.since(30.minutes.ago)).not_to include(fail_a)
      expect(described_class.since(30.minutes.ago)).to include(fail_b)
    end

    it "for_ip filters by exact ip" do
      hit = create(:login_attempt, ip: "9.9.9.9", ip_prefix: "9.9.9.0/24")
      expect(described_class.for_ip("9.9.9.9")).to contain_exactly(hit)
    end
  end

  describe "callback: resolved_at on result flip" do
    it "stamps resolved_at when transitioning out of pending_approval" do
      row = create(:login_attempt, :pending)
      expect(row.resolved_at).to be_nil

      row.update!(result: :success, reason: :new_location_2fa_passed)
      expect(row.resolved_at).to be_within(1.second).of(Time.current)
    end

    it "does not stamp resolved_at on rows that never were pending" do
      row = create(:login_attempt)
      row.update!(reason: :rate_limited)
      expect(row.resolved_at).to be_nil
    end

    it "preserves a manually-set resolved_at" do
      row = create(:login_attempt, :pending)
      stamp = 5.minutes.ago.change(usec: 0)
      row.update!(result: :blocked, reason: :blocked_from_web, resolved_at: stamp)
      expect(row.resolved_at).to be_within(1.second).of(stamp)
    end
  end

  describe "#fingerprint_short" do
    it "returns the first 12 hex chars" do
      row = build(:login_attempt, fingerprint_hash: "a" * 64)
      expect(row.fingerprint_short).to eq("a" * 12)
    end
  end

  describe "#geo_summary" do
    it "returns 'city, country (region)' when all three are present" do
      row = build(:login_attempt, :with_geo)
      expect(row.geo_summary).to eq("Bucharest, RO (Bucharest)")
    end

    it "returns 'city, country' when region is blank" do
      row = build(:login_attempt, geo_city: "Berlin", geo_country: "DE")
      expect(row.geo_summary).to eq("Berlin, DE")
    end

    it "returns nil when all geo fields are blank" do
      row = build(:login_attempt)
      expect(row.geo_summary).to be_nil
    end
  end
end
