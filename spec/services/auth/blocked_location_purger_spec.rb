require "rails_helper"

RSpec.describe Auth::BlockedLocationPurger do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe "happy paths" do
    it "hard-deletes rows matching source_surface" do
      keep    = create(:blocked_location, source_surface: :tui)
      delete1 = create(:blocked_location, source_surface: :web)
      delete2 = create(:blocked_location, source_surface: :web)

      result = described_class.call(filter: { source_surface: "web" }, acting_user: user)

      expect(result.deleted_count).to eq(2)
      expect(BlockedLocation.where(id: [ delete1.id, delete2.id ])).to be_empty
      expect(BlockedLocation.find_by(id: keep.id)).to be_present
    end

    it "deletes by fingerprint" do
      target = create(:blocked_location, fingerprint_hash: "f" * 64)
      keep   = create(:blocked_location)

      result = described_class.call(filter: { fingerprint: "f" * 64 }, acting_user: user)

      expect(result.deleted_count).to eq(1)
      expect(BlockedLocation.find_by(id: target.id)).to be_nil
      expect(BlockedLocation.find_by(id: keep.id)).to be_present
    end

    it "deletes by ip_prefix" do
      target = create(:blocked_location, ip_prefix: "192.168.1.0/24")
      keep   = create(:blocked_location, ip_prefix: "10.0.0.0/24")

      result = described_class.call(filter: { ip_prefix: "192.168.1.0/24" })

      expect(result.deleted_count).to eq(1)
      expect(BlockedLocation.find_by(id: target.id)).to be_nil
      expect(BlockedLocation.find_by(id: keep.id)).to be_present
    end

    it "deletes by since timestamp" do
      old_row = travel_to(2.days.ago) { create(:blocked_location) }
      new_row = create(:blocked_location)

      result = described_class.call(filter: { since: 1.day.ago.iso8601 })

      expect(result.deleted_count).to eq(1)
      expect(BlockedLocation.find_by(id: new_row.id)).to be_nil
      expect(BlockedLocation.find_by(id: old_row.id)).to be_present
    end

    it "deletes only active rows when active=yes" do
      active   = create(:blocked_location, source_surface: :web)
      unblocked = create(:blocked_location, :unblocked, source_surface: :web)

      result = described_class.call(filter: { active: "yes", source_surface: "web" })

      expect(result.deleted_count).to eq(1)
      expect(BlockedLocation.find_by(id: active.id)).to be_nil
      expect(BlockedLocation.find_by(id: unblocked.id)).to be_present
    end

    it "deletes only soft-unblocked rows when active=no" do
      active    = create(:blocked_location, source_surface: :web)
      unblocked = create(:blocked_location, :unblocked, source_surface: :web)

      result = described_class.call(filter: { active: "no", source_surface: "web" })

      expect(result.deleted_count).to eq(1)
      expect(BlockedLocation.find_by(id: unblocked.id)).to be_nil
      expect(BlockedLocation.find_by(id: active.id)).to be_present
    end

    it "echoes the filter back in the result" do
      create(:blocked_location, source_surface: :web)
      result = described_class.call(filter: { source_surface: "web" })
      expect(result.filter[:source_surface]).to eq("web")
    end
  end

  describe "sad paths" do
    it "raises EmptyFilter on a wholly empty filter hash" do
      create(:blocked_location)
      expect {
        described_class.call(filter: {})
      }.to raise_error(described_class::EmptyFilter)
    end

    it "raises EmptyFilter when every filter value is blank" do
      create(:blocked_location)
      expect {
        described_class.call(filter: { source_surface: "", fingerprint: nil })
      }.to raise_error(described_class::EmptyFilter)
    end

    it "raises InvalidFilter on a malformed since" do
      expect {
        described_class.call(filter: { since: "not-iso" })
      }.to raise_error(described_class::InvalidFilter, /since/)
    end

    it "raises InvalidFilter on a malformed until_ts" do
      expect {
        described_class.call(filter: { until_ts: "garbage" })
      }.to raise_error(described_class::InvalidFilter, /until_ts/)
    end
  end

  describe "edge cases" do
    it "returns deleted_count=0 when no rows match the filter" do
      result = described_class.call(filter: { fingerprint: "z" * 64 })
      expect(result.deleted_count).to eq(0)
    end

    it "batches large delete sets" do
      # Stub the constant low so the batched loop runs > 1 iteration
      # without inserting thousands of rows.
      stub_const("#{described_class}::BATCH_SIZE", 2)

      5.times { create(:blocked_location, source_surface: :web) }
      create(:blocked_location, source_surface: :tui)

      result = described_class.call(filter: { source_surface: "web" })

      expect(result.deleted_count).to eq(5)
      expect(BlockedLocation.where(source_surface: :web)).to be_empty
      expect(BlockedLocation.where(source_surface: :tui).count).to eq(1)
    end
  end

  describe "scope safety (flaw checks)" do
    it "does not touch login_attempts rows" do
      attempt = create(:login_attempt)
      target  = create(:blocked_location, fingerprint_hash: "x" * 64)

      described_class.call(filter: { fingerprint: "x" * 64 })

      expect(LoginAttempt.find_by(id: attempt.id)).to be_present
      expect(BlockedLocation.find_by(id: target.id)).to be_nil
    end
  end
end
