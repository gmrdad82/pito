require "rails_helper"

# Phase 8 — tenant drop. Collection is install-wide.
RSpec.describe Collection, type: :model do
  subject { build(:collection) }

  describe "associations" do
    it "does not declare a tenant association" do
      expect(Collection.reflect_on_association(:tenant)).to be_nil
    end
    it { is_expected.to have_many(:games).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "default name" do
    it 'defaults to "Untitled collection"' do
      collection = Collection.create!
      expect(collection.name).to eq("Untitled collection")
    end
  end
end
