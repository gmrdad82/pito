require "rails_helper"

RSpec.describe VideoWindowSummary, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "window enum" do
    it "casts window to one of the analytics_window values" do
      record = create(:video_window_summary, :seven_d)
      expect(record.window).to eq("7d")
    end

    it "rejects an unknown window value" do
      # Postgres `analytics_window` enum rejects out-of-range strings
      # at the wire level. Assert the DB-side rejection rather than
      # the Rails-side validation message.
      video = create(:video)
      expect {
        described_class.create!(
          video: video,
          window: "bogus",
          window_start: 7.days.ago.to_date,
          window_end: Date.current
        )
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "round-trips each of the four window values" do
      video = create(:video)
      %w[7d 28d 90d lifetime].each_with_index do |w, idx|
        record = create(:video_window_summary,
                        video: video,
                        window: w,
                        window_start: (idx + 1).days.ago.to_date - idx.years,
                        window_end: Date.current - idx.days)
        record.reload
        expect(record.window).to eq(w), "expected #{w} round-trip"
      end
    end
  end

  describe "validations" do
    it "is invalid without window_start" do
      record = build(:video_window_summary, window_start: nil)
      expect(record).not_to be_valid
      expect(record.errors[:window_start]).to include("can't be blank")
    end

    it "is invalid without window_end" do
      record = build(:video_window_summary, window_end: nil)
      expect(record).not_to be_valid
      expect(record.errors[:window_end]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, window)" do
      existing = create(:video_window_summary, :twenty_eight_d)
      duplicate = build(:video_window_summary, :twenty_eight_d,
                        video: existing.video)
      expect(duplicate).not_to be_valid
    end
  end

  describe "non-summable ratios" do
    it "stores non-summable ratios as nullable numerics" do
      record = create(:video_window_summary,
                      average_view_percentage: 47.123456,
                      video_thumbnail_impressions_click_rate: 0.085,
                      card_click_rate: 0.012345,
                      card_teaser_click_rate: 0.067890)
      record.reload
      expect(record.average_view_percentage).to eq(BigDecimal("47.123456"))
      expect(record.video_thumbnail_impressions_click_rate).to eq(BigDecimal("0.085000"))
      expect(record.card_click_rate).to eq(BigDecimal("0.012345"))
      expect(record.card_teaser_click_rate).to eq(BigDecimal("0.067890"))
    end

    it "permits NULL for every non-summable ratio" do
      record = create(:video_window_summary,
                      average_view_percentage: nil,
                      video_thumbnail_impressions_click_rate: nil,
                      card_click_rate: nil,
                      card_teaser_click_rate: nil)
      expect(record).to be_valid
    end
  end

  describe "monetization columns" do
    it "stores monetization columns as NULL until set" do
      record = create(:video_window_summary)
      %i[
        estimated_revenue estimated_ad_revenue gross_revenue
        estimated_red_partner_revenue monetized_playbacks
        ad_impressions playback_based_cpm cpm
      ].each do |attr|
        expect(record.public_send(attr)).to be_nil
      end
    end
  end

  describe "scopes" do
    it "seven_d / twenty_eight_d / ninety_d / lifetime each filter by window" do
      video = create(:video)
      seven   = create(:video_window_summary, :seven_d,        video: video)
      twenty  = create(:video_window_summary, :twenty_eight_d, video: video)
      ninety  = create(:video_window_summary, :ninety_d,       video: video)
      life    = create(:video_window_summary, :lifetime,       video: video)
      expect(described_class.seven_d).to        include(seven)
      expect(described_class.seven_d).not_to    include(twenty)
      expect(described_class.twenty_eight_d).to include(twenty)
      expect(described_class.twenty_eight_d).not_to include(ninety)
      expect(described_class.ninety_d).to       include(ninety)
      expect(described_class.ninety_d).not_to   include(life)
      expect(described_class.lifetime).to       include(life)
      expect(described_class.lifetime).not_to   include(seven)
    end
  end
end
