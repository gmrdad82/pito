require "rails_helper"

RSpec.describe Tenant, type: :model do
  subject { build(:tenant) }

  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:destroy) }
    it { is_expected.to have_many(:channels).dependent(:destroy) }
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
end
