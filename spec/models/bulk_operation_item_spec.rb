require "rails_helper"

RSpec.describe BulkOperationItem, type: :model do
  subject { build(:bulk_operation_item) }

  describe "associations" do
    it { is_expected.to belong_to(:bulk_operation) }
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:video_id).scoped_to(:bulk_operation_id) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, succeeded: 1, failed: 2).with_prefix(:status) }
  end
end
