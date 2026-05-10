require "rails_helper"

RSpec.describe VideoDailyByAgeGroupGender, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without an age_group" do
      record = build(:video_daily_by_age_group_gender, age_group: nil)
      expect(record).not_to be_valid
      expect(record.errors[:age_group]).to include("can't be blank")
    end

    it "is invalid without a gender" do
      record = build(:video_daily_by_age_group_gender, gender: nil)
      expect(record).not_to be_valid
      expect(record.errors[:gender]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, age_group, gender)" do
      existing = create(:video_daily_by_age_group_gender)
      duplicate = build(:video_daily_by_age_group_gender,
                        video: existing.video,
                        date: existing.date,
                        age_group: existing.age_group,
                        gender: existing.gender)
      expect(duplicate).not_to be_valid
    end
  end

  describe "viewer_percentage default" do
    it "defaults to 0 not NULL" do
      record = build(:video_daily_by_age_group_gender, viewer_percentage: nil)
      # NOT NULL with default 0 — provide nil and the column will reject
      # the write at the DB level. Build then save and assert the
      # column-level NOT NULL surfaces.
      expect { record.save(validate: false) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rounds-trips fractional viewer_percentage at 6 decimals" do
      record = create(:video_daily_by_age_group_gender,
                      viewer_percentage: 12.345678)
      record.reload
      expect(record.viewer_percentage).to eq(BigDecimal("12.345678"))
    end
  end

  describe "scopes" do
    describe ".for_age_group" do
      it "filters by age_group" do
        video = create(:video)
        a = create(:video_daily_by_age_group_gender, video: video,
                   age_group: "AGE_18_24", gender: "FEMALE", date: 1.day.ago.to_date)
        b = create(:video_daily_by_age_group_gender, video: video,
                   age_group: "AGE_25_34", gender: "FEMALE", date: 2.days.ago.to_date)
        expect(described_class.for_age_group("AGE_18_24")).to include(a)
        expect(described_class.for_age_group("AGE_18_24")).not_to include(b)
      end
    end

    describe ".for_gender" do
      it "filters by gender" do
        video = create(:video)
        f = create(:video_daily_by_age_group_gender, video: video,
                   age_group: "AGE_18_24", gender: "FEMALE", date: 1.day.ago.to_date)
        m = create(:video_daily_by_age_group_gender, video: video,
                   age_group: "AGE_18_24", gender: "MALE", date: 2.days.ago.to_date)
        expect(described_class.for_gender("FEMALE")).to include(f)
        expect(described_class.for_gender("FEMALE")).not_to include(m)
      end
    end
  end
end
