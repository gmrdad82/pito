require "rails_helper"

RSpec.describe BulkOperationItem, type: :model do
  subject { build(:bulk_operation_item) }

  describe "associations" do
    it { is_expected.to belong_to(:bulk_operation) }
    it { is_expected.to belong_to(:video).optional }
    it { is_expected.to belong_to(:target).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:target_type) }
    it { is_expected.to validate_presence_of(:target_id) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, succeeded: 1, failed: 2, skipped: 3).with_prefix(:status) }

    it "accepts skipped (3) as a valid status" do
      item = build_stubbed(:bulk_operation_item, status: :skipped)
      expect(item).to be_valid
      expect(item.status).to eq("skipped")
      expect(BulkOperationItem.statuses["skipped"]).to eq(3)
    end
  end
end
