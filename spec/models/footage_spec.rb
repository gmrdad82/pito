# frozen_string_literal: true

require "rails_helper"

RSpec.describe Footage, type: :model do
  subject(:footage) { build(:footage) }

  describe "associations" do
    it { is_expected.to belong_to(:game).required }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:filename) }
    it { is_expected.to validate_uniqueness_of(:filename).scoped_to(:game_id) }
  end
end
