require "rails_helper"

RSpec.describe Production, type: :model do
  subject { build(:production) }

  describe "associations" do
    it { is_expected.to belong_to(:video).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:status)
        .with_values(idea: 0, in_progress: 1, published: 2, archived: 3)
    }
  end
end
