require "rails_helper"

RSpec.describe BulkOperation, type: :model do
  subject { build(:bulk_operation) }

  describe "associations" do
    it { is_expected.to have_many(:bulk_operation_items).dependent(:destroy) }
    it { is_expected.to have_many(:videos).through(:bulk_operation_items) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:kind) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:kind).with_values(update_metadata: 0, update_privacy: 1, add_to_playlist: 2, remove_from_playlist: 3) }
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, running: 1, completed: 2, failed: 3).with_prefix(:status) }
  end
end
