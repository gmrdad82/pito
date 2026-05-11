require "rails_helper"

RSpec.describe Auth::BlockedLocationLister do
  include ActiveSupport::Testing::TimeHelpers

  let(:user1) { create(:user) }
  let(:user2) { create(:user) }

  describe "happy paths" do
    let!(:old_row) do
      travel_to(3.days.ago) do
        create(:blocked_location, blocked_by_user: user1, source_surface: :web,
                                  fingerprint_hash: "a" * 64, ip_prefix: "1.0.0.0/24")
      end
    end
    let!(:mid_row) do
      travel_to(1.day.ago) do
        create(:blocked_location, blocked_by_user: user2, source_surface: :tui,
                                  fingerprint_hash: "b" * 64, ip_prefix: "2.0.0.0/24")
      end
    end
    let!(:recent_row) do
      travel_to(1.hour.ago) do
        create(:blocked_location, blocked_by_user: user1, source_surface: :mcp,
                                  fingerprint_hash: "c" * 64, ip_prefix: "3.0.0.0/24")
      end
    end
    let!(:unblocked_row) do
      travel_to(2.hours.ago) do
        create(:blocked_location, :unblocked, blocked_by_user: user1, source_surface: :web,
                                              fingerprint_hash: "d" * 64, ip_prefix: "4.0.0.0/24")
      end
    end

    it "returns rows sorted desc by blocked_at" do
      result = described_class.call
      expect(result.rows.map(&:id).first).to eq(recent_row.id)
      expect(result.rows.map(&:id).last).to eq(old_row.id)
    end

    it "reports the total + page + per_page" do
      result = described_class.call(per_page: 2)
      expect(result.total).to eq(4)
      expect(result.page).to eq(1)
      expect(result.per_page).to eq(2)
      expect(result.rows.size).to eq(2)
    end

    it "page 2 returns the next slice" do
      page1 = described_class.call(per_page: 2, page: 1).rows.map(&:id)
      page2 = described_class.call(per_page: 2, page: 2).rows.map(&:id)
      expect((page1 & page2)).to be_empty
    end

    it "filters by source_surface" do
      result = described_class.call(filters: { source_surface: "tui" })
      expect(result.rows.map(&:id)).to contain_exactly(mid_row.id)
    end

    it "filters by blocked_by_user_id" do
      result = described_class.call(filters: { blocked_by_user_id: user2.id })
      expect(result.rows.map(&:id)).to contain_exactly(mid_row.id)
    end

    it "filters by since" do
      result = described_class.call(filters: { since: 2.days.ago.iso8601 })
      ids = result.rows.map(&:id)
      expect(ids).to include(mid_row.id, recent_row.id)
      expect(ids).not_to include(old_row.id)
    end

    it "filters by until_ts" do
      result = described_class.call(filters: { until_ts: 2.days.ago.iso8601 })
      ids = result.rows.map(&:id)
      expect(ids).to include(old_row.id)
      expect(ids).not_to include(recent_row.id)
    end

    it "filters by fingerprint exact match" do
      result = described_class.call(filters: { fingerprint: "a" * 64 })
      expect(result.rows.map(&:id)).to contain_exactly(old_row.id)
    end

    it "filters by ip_prefix exact match" do
      result = described_class.call(filters: { ip_prefix: "3.0.0.0/24" })
      expect(result.rows.map(&:id)).to contain_exactly(recent_row.id)
    end

    it "filters active=yes (returns active rows only)" do
      result = described_class.call(filters: { active: "yes" })
      ids = result.rows.map(&:id)
      expect(ids).to include(old_row.id, mid_row.id, recent_row.id)
      expect(ids).not_to include(unblocked_row.id)
    end

    it "filters active=no (returns soft-unblocked rows only)" do
      result = described_class.call(filters: { active: "no" })
      expect(result.rows.map(&:id)).to contain_exactly(unblocked_row.id)
    end

    it "active=anything else returns both" do
      result = described_class.call(filters: { active: "" })
      expect(result.rows.size).to eq(4)
    end

    it "echoes applied filters back in the result" do
      result = described_class.call(filters: { source_surface: "web", active: "yes" })
      expect(result.filters[:source_surface]).to eq("web")
      expect(result.filters[:active]).to eq("yes")
    end

    it "intersects filters AND-wise" do
      result = described_class.call(filters: { source_surface: "web", active: "yes" })
      expect(result.rows.map(&:id)).to contain_exactly(old_row.id)
    end
  end

  describe "sad paths" do
    it "raises InvalidFilter on a malformed since" do
      expect {
        described_class.call(filters: { since: "not-iso" })
      }.to raise_error(described_class::InvalidFilter, /since/)
    end

    it "raises InvalidFilter on a malformed until_ts" do
      expect {
        described_class.call(filters: { until_ts: "garbage" })
      }.to raise_error(described_class::InvalidFilter, /until_ts/)
    end

    it "ignores an unknown source_surface (rather than erroring)" do
      create(:blocked_location)
      result = described_class.call(filters: { source_surface: "nonsense" })
      # Filter is silently dropped — returns all rows.
      expect(result.rows.size).to eq(1)
    end
  end

  describe "pagination clamping" do
    it "clamps per_page at MAX_PER_PAGE" do
      result = described_class.call(per_page: 999)
      expect(result.per_page).to eq(described_class::MAX_PER_PAGE)
    end

    it "clamps page below 1 up to 1" do
      result = described_class.call(page: -3)
      expect(result.page).to eq(1)
    end

    it "clamps per_page below 1 up to 1" do
      result = described_class.call(per_page: 0)
      expect(result.per_page).to eq(1)
    end
  end
end
