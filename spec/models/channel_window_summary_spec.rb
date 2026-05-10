require "rails_helper"

RSpec.describe ChannelWindowSummary, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
  end

  describe "window enum" do
    it "casts window to one of the analytics_window values" do
      record = create(:channel_window_summary, :seven_d)
      expect(record.window).to eq("7d")
    end

    it "rejects an unknown window value" do
      record = build(:channel_window_summary, window: "bogus")
      expect(record).not_to be_valid
      expect(record.errors[:window]).to be_present
    end

    it "round-trips each of the four window values" do
      channel = create(:channel)
      %w[7d 28d 90d lifetime].each_with_index do |w, idx|
        record = create(:channel_window_summary,
                        channel: channel,
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
      record = build(:channel_window_summary, window_start: nil)
      expect(record).not_to be_valid
      expect(record.errors[:window_start]).to include("can't be blank")
    end

    it "is invalid without window_end" do
      record = build(:channel_window_summary, window_end: nil)
      expect(record).not_to be_valid
      expect(record.errors[:window_end]).to include("can't be blank")
    end

    it "is invalid with a duplicate (channel_id, window)" do
      existing = create(:channel_window_summary, :twenty_eight_d)
      duplicate = build(:channel_window_summary, :twenty_eight_d,
                        channel: existing.channel)
      expect(duplicate).not_to be_valid
    end
  end

  describe "non-summable ratios" do
    it "stores non-summable ratios as nullable numerics" do
      record = create(:channel_window_summary,
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
      record = create(:channel_window_summary,
                      average_view_percentage: nil,
                      video_thumbnail_impressions_click_rate: nil,
                      card_click_rate: nil,
                      card_teaser_click_rate: nil)
      expect(record).to be_valid
    end
  end

  describe "monetization columns" do
    it "stores monetization columns as NULL until set" do
      record = create(:channel_window_summary)
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
      channel = create(:channel)
      seven   = create(:channel_window_summary, :seven_d,        channel: channel)
      twenty  = create(:channel_window_summary, :twenty_eight_d, channel: channel)
      ninety  = create(:channel_window_summary, :ninety_d,       channel: channel)
      life    = create(:channel_window_summary, :lifetime,       channel: channel)
      expect(described_class.seven_d).to        include(seven).and(exclude(twenty))
      expect(described_class.twenty_eight_d).to include(twenty).and(exclude(ninety))
      expect(described_class.ninety_d).to       include(ninety).and(exclude(life))
      expect(described_class.lifetime).to       include(life).and(exclude(seven))
    end
  end
end
