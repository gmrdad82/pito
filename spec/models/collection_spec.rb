require "rails_helper"

RSpec.describe Collection, type: :model do
  subject { build(:collection) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to have_many(:games).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "default name" do
    it 'defaults to "Untitled collection"' do
      tenant = create(:tenant)
      collection = Collection.create!(tenant: tenant)
      expect(collection.name).to eq("Untitled collection")
    end
  end
end
