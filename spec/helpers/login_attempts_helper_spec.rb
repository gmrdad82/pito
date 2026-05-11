require "rails_helper"

RSpec.describe LoginAttemptsHelper, type: :helper do
  describe "#login_attempt_result_label" do
    it "maps each enum value to its human label" do
      [
        [ :success,          "success" ],
        [ :failed,           "failed" ],
        [ :pending_approval, "pending approval" ],
        [ :blocked,          "blocked" ],
        [ :rate_limited,     "rate limited" ]
      ].each do |result, label|
        attempt = build(:login_attempt, result: result, reason: :wrong_password)
        expect(helper.login_attempt_result_label(attempt)).to eq(label)
      end
    end
  end

  describe "#login_attempt_reason_label" do
    it "maps wrong_password → 'wrong password'" do
      attempt = build(:login_attempt, reason: :wrong_password)
      expect(helper.login_attempt_reason_label(attempt)).to eq("wrong password")
    end

    it "maps trusted_location_success → 'trusted location'" do
      attempt = build(:login_attempt, :success, reason: :trusted_location_success)
      expect(helper.login_attempt_reason_label(attempt)).to eq("trusted location")
    end

    it "maps blocked_pair → 'blocked location'" do
      attempt = build(:login_attempt, :blocked)
      expect(helper.login_attempt_reason_label(attempt)).to eq("blocked location")
    end
  end

  describe "#login_attempt_geo_label" do
    it "renders city + country + region when present" do
      attempt = build(:login_attempt, :with_geo)
      expect(helper.login_attempt_geo_label(attempt)).to eq("Bucharest, RO (Bucharest)")
    end

    it "renders 'city, country' when region is blank" do
      attempt = build(:login_attempt, geo_city: "Berlin", geo_country: "DE")
      expect(helper.login_attempt_geo_label(attempt)).to eq("Berlin, DE")
    end

    it "renders city-only when country missing" do
      attempt = build(:login_attempt, geo_city: "OnlyCity")
      expect(helper.login_attempt_geo_label(attempt)).to eq("OnlyCity")
    end

    it "renders country-only when city missing" do
      attempt = build(:login_attempt, geo_country: "US")
      expect(helper.login_attempt_geo_label(attempt)).to eq("US")
    end

    it "renders 'location unknown' when geo entirely blank" do
      attempt = build(:login_attempt)
      expect(helper.login_attempt_geo_label(attempt)).to eq("location unknown")
    end
  end

  describe "#login_attempt_result_css" do
    it "blocked → text-danger" do
      attempt = build(:login_attempt, :blocked)
      expect(helper.login_attempt_result_css(attempt)).to eq("text-danger")
    end

    it "failed → text-muted" do
      attempt = build(:login_attempt)
      expect(helper.login_attempt_result_css(attempt)).to eq("text-muted")
    end

    it "success → empty string (no special class)" do
      attempt = build(:login_attempt, :success)
      expect(helper.login_attempt_result_css(attempt)).to eq("")
    end
  end
end
