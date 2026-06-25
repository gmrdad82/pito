# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsPrimitive, type: :model do
  describe "factory" do
    it "has a working factory" do
      expect(build(:analytics_primitive)).to be_valid
    end
  end

  # ── validations ──────────────────────────────────────────────────────────────

  describe "validations" do
    it "requires video_youtube_id" do
      expect(build(:analytics_primitive, video_youtube_id: nil)).not_to be_valid
    end

    it "requires period_token" do
      expect(build(:analytics_primitive, period_token: nil)).not_to be_valid
    end

    it "requires start_date" do
      expect(build(:analytics_primitive, start_date: nil)).not_to be_valid
    end

    it "requires end_date" do
      expect(build(:analytics_primitive, end_date: nil)).not_to be_valid
    end

    it "requires fetched_at" do
      expect(build(:analytics_primitive, fetched_at: nil)).not_to be_valid
    end

    describe "report inclusion" do
      it "accepts every value in REPORTS" do
        described_class::REPORTS.each do |r|
          expect(build(:analytics_primitive, report: r)).to be_valid, "expected #{r.inspect} to be valid"
        end
      end

      it "rejects an unknown report" do
        expect(build(:analytics_primitive, report: "bogus")).not_to be_valid
      end

      it "rejects a nil report" do
        expect(build(:analytics_primitive, report: nil)).not_to be_valid
      end
    end

    describe "uniqueness on (video_youtube_id, report, start_date, end_date)" do
      let(:start_date) { Date.new(2026, 1, 1) }
      let(:end_date)   { Date.new(2026, 1, 31) }

      before do
        create(:analytics_primitive,
               video_youtube_id: "uniq_vid",
               report:           "scalars",
               start_date:       start_date,
               end_date:         end_date)
      end

      it "is invalid when the same (video, report, start, end) tuple already exists" do
        dup = build(:analytics_primitive,
                    video_youtube_id: "uniq_vid",
                    report:           "scalars",
                    start_date:       start_date,
                    end_date:         end_date)
        expect(dup).not_to be_valid
        expect(dup.errors[:video_youtube_id]).to be_present
      end

      it "raises at the DB level when saved with validate: false" do
        dup = build(:analytics_primitive,
                    video_youtube_id: "uniq_vid",
                    report:           "scalars",
                    start_date:       start_date,
                    end_date:         end_date)
        expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "is valid with a different report" do
        expect(
          build(:analytics_primitive,
                video_youtube_id: "uniq_vid",
                report:           "daily",
                start_date:       start_date,
                end_date:         end_date)
        ).to be_valid
      end

      it "is valid with a different start_date" do
        expect(
          build(:analytics_primitive,
                video_youtube_id: "uniq_vid",
                report:           "scalars",
                start_date:       start_date + 1,
                end_date:         end_date)
        ).to be_valid
      end

      it "is valid with a different end_date" do
        expect(
          build(:analytics_primitive,
                video_youtube_id: "uniq_vid",
                report:           "scalars",
                start_date:       start_date,
                end_date:         end_date + 1)
        ).to be_valid
      end

      it "is valid with a different video_youtube_id" do
        expect(
          build(:analytics_primitive,
                video_youtube_id: "other_vid",
                report:           "scalars",
                start_date:       start_date,
                end_date:         end_date)
        ).to be_valid
      end
    end
  end

  # ── #frozen? ─────────────────────────────────────────────────────────────────

  describe "#frozen?" do
    it "returns true when expires_at is nil" do
      expect(build(:analytics_primitive, :frozen)).to be_frozen
    end

    it "returns false when expires_at is in the future" do
      expect(build(:analytics_primitive, :live)).not_to be_frozen
    end

    it "returns false when expires_at is in the past" do
      expect(build(:analytics_primitive, :expired)).not_to be_frozen
    end
  end

  # ── #expired? ────────────────────────────────────────────────────────────────

  describe "#expired?" do
    it "returns false when expires_at is nil (frozen rows never expire)" do
      expect(build(:analytics_primitive, :frozen)).not_to be_expired
    end

    it "returns false when expires_at is in the future" do
      expect(build(:analytics_primitive, :live)).not_to be_expired
    end

    it "returns true when expires_at is in the past" do
      expect(build(:analytics_primitive, :expired)).to be_expired
    end
  end

  # ── #live? ───────────────────────────────────────────────────────────────────

  describe "#live?" do
    it "returns true when expires_at is nil (frozen = usable forever)" do
      expect(build(:analytics_primitive, :frozen)).to be_live
    end

    it "returns true when expires_at is in the future" do
      expect(build(:analytics_primitive, :live)).to be_live
    end

    it "returns false when expires_at is in the past" do
      expect(build(:analytics_primitive, :expired)).not_to be_live
    end
  end

  # ── .expired scope ───────────────────────────────────────────────────────────

  describe ".expired scope" do
    it "includes rows whose expires_at is in the past" do
      expired_row = create(:analytics_primitive, :expired)
      expect(described_class.expired).to include(expired_row)
    end

    it "excludes rows whose expires_at is in the future (live)" do
      live_row = create(:analytics_primitive, :live)
      expect(described_class.expired).not_to include(live_row)
    end

    it "excludes rows with nil expires_at (frozen — never swept)" do
      frozen_row = create(:analytics_primitive, :frozen)
      expect(described_class.expired).not_to include(frozen_row)
    end
  end
end
