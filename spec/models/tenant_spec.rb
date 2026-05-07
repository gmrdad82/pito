require "rails_helper"

RSpec.describe Tenant, type: :model do
  subject { build(:tenant) }

  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:destroy) }
    it { is_expected.to have_many(:channels).dependent(:destroy) }

    # Phase 4 — Project Workspace associations.
    it { is_expected.to have_many(:projects).dependent(:destroy) }
    it { is_expected.to have_many(:collections).dependent(:destroy) }
    it { is_expected.to have_many(:games).dependent(:destroy) }
    it { is_expected.to have_many(:footages).dependent(:destroy) }
    it { is_expected.to have_many(:notes).dependent(:destroy) }
    it { is_expected.to have_many(:timelines).dependent(:destroy) }
  end

  describe "notes_syncing_at column (Phase 4 §3.7)" do
    it "exists and is nullable" do
      tenant = create(:tenant)
      expect(tenant.notes_syncing_at).to be_nil

      tenant.update!(notes_syncing_at: Time.current)
      expect(tenant.reload.notes_syncing_at).to be_present
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "rejects names shorter than 3 characters" do
      tenant = build(:tenant, name: "ab")
      expect(tenant).not_to be_valid
      expect(tenant.errors[:name]).to be_present
    end

    it "accepts names exactly 3 characters" do
      expect(build(:tenant, name: "abc")).to be_valid
    end

    it "accepts names exactly 30 characters" do
      expect(build(:tenant, name: "a" * 30)).to be_valid
    end

    it "rejects names longer than 30 characters" do
      tenant = build(:tenant, name: "a" * 31)
      expect(tenant).not_to be_valid
      expect(tenant.errors[:name]).to be_present
    end
  end

  # Phase 5A §5.3 — `tenants.slug` is the canonical citext unique
  # URL-safe identifier.
  describe "slug validations (Phase 5A §5.3)" do
    it "requires a slug" do
      tenant = build(:tenant, slug: nil)
      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to include("can't be blank")
    end

    it "accepts a typical slug" do
      expect(build(:tenant, slug: "primary")).to be_valid
      expect(build(:tenant, slug: "team-alpha")).to be_valid
      expect(build(:tenant, slug: "team_42")).to be_valid
      expect(build(:tenant, slug: "0u812")).to be_valid
    end

    it "rejects slugs with uppercase letters" do
      tenant = build(:tenant, slug: "Primary")
      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to be_present
    end

    it "rejects slugs that start with a hyphen or underscore" do
      expect(build(:tenant, slug: "-primary")).not_to be_valid
      expect(build(:tenant, slug: "_primary")).not_to be_valid
    end

    it "rejects slugs with spaces or punctuation" do
      expect(build(:tenant, slug: "team alpha")).not_to be_valid
      expect(build(:tenant, slug: "team!")).not_to be_valid
      expect(build(:tenant, slug: "team.alpha")).not_to be_valid
    end

    it "rejects slugs longer than 60 characters" do
      tenant = build(:tenant, slug: "a" * 61)
      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to be_present
    end

    it "is unique (case-insensitive via citext)" do
      create(:tenant, slug: "shared-slug")
      dup = build(:tenant, slug: "Shared-Slug")
      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
    end
  end
end
