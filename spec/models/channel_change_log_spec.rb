require "rails_helper"

# Phase 7.5 §11a — Channel Schema + Sync Foundation.
RSpec.describe ChannelChangeLog, type: :model do
  let(:user)    { create(:user) }
  let(:channel) { create(:channel) }
  let(:base_attrs) do
    {
      channel: channel,
      changed_by_user: user,
      field: "title",
      old_value: "Old title",
      new_value: "New title",
      changed_at: Time.current
    }
  end

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:changed_by_user).class_name("User") }
  end

  describe "validations" do
    it "is valid with the canonical attribute set" do
      expect(described_class.new(base_attrs)).to be_valid
    end

    describe "field" do
      it "is required" do
        record = described_class.new(base_attrs.merge(field: nil))
        expect(record).not_to be_valid
        expect(record.errors[:field]).to be_present
      end

      it "accepts `title`" do
        expect(described_class.new(base_attrs.merge(field: "title"))).to be_valid
      end

      it "accepts `handle`" do
        expect(described_class.new(base_attrs.merge(field: "handle"))).to be_valid
      end

      it "rejects values outside the documented set" do
        record = described_class.new(base_attrs.merge(field: "description"))
        expect(record).not_to be_valid
        expect(record.errors[:field]).to be_present
      end
    end

    describe "new_value" do
      it "is required" do
        record = described_class.new(base_attrs.merge(new_value: nil))
        expect(record).not_to be_valid
        expect(record.errors[:new_value]).to be_present
      end
    end

    describe "changed_at" do
      it "is required" do
        record = described_class.new(base_attrs.merge(changed_at: nil))
        expect(record).not_to be_valid
        expect(record.errors[:changed_at]).to be_present
      end
    end

    describe "old_value" do
      it "permits nil (first push has no prior value)" do
        record = described_class.new(base_attrs.merge(old_value: nil))
        expect(record).to be_valid
      end
    end
  end

  describe ".recent scope" do
    it "returns up to 20 rows ordered by changed_at descending" do
      now = Time.current
      25.times do |i|
        described_class.create!(
          channel: channel, changed_by_user: user,
          field: "title", new_value: "T#{i}",
          changed_at: now - i.hours
        )
      end
      result = described_class.recent
      expect(result.size).to eq(20)
      expect(result.map(&:changed_at)).to eq(result.map(&:changed_at).sort.reverse)
    end
  end

  describe "append-only enforcement" do
    let!(:record) { described_class.create!(base_attrs) }

    it "is `readonly?` once persisted" do
      expect(record.readonly?).to be(true)
    end

    it "raises ActiveRecord::ReadOnlyRecord on update!" do
      expect { record.update!(new_value: "Tampered") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on update (no bang)" do
      expect { record.update(new_value: "Tampered") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy" do
      expect { record.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ActiveRecord::ReadOnlyRecord on destroy!" do
      expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
