require "rails_helper"

RSpec.describe Note, type: :model do
  subject { build(:note) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "enums" do
    it {
      is_expected.to define_enum_for(:kind)
        .with_values(idea: 0, log: 1, todo: 2, reference: 3)
    }
  end
end
