require "rails_helper"

# Phase 26 — 01a. Timezone foundation request surface.
#
# `PATCH /settings/time_zone` is the single endpoint behind the
# Settings dropdown form AND the first-load Stimulus detect flow. Both
# callers post the same `{ time_zone: <name> }` shape; HTML responses
# redirect with flash, non-HTML responses return 204 / 422.
RSpec.describe "Settings::TimeZone", type: :request do
  let(:password) { "supersecret123" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end

  before do |example|
    next if example.metadata[:unauthenticated]
    user.update!(password: password, password_confirmation: password)
    sign_in_as(user)
  end

  describe "PATCH /settings/time_zone (HTML, Settings dropdown caller)" do
    it "updates the user's time_zone to a valid IANA name" do
      patch settings_time_zone_path, params: { time_zone: "Europe/Bucharest" }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.time_zone).to eq("Europe/Bucharest")
    end

    it "accepts the Pacific/Kiritimati edge zone (UTC+14)" do
      patch settings_time_zone_path, params: { time_zone: "Pacific/Kiritimati" }

      expect(response).to redirect_to(settings_path)
      expect(user.reload.time_zone).to eq("Pacific/Kiritimati")
    end

    it "accepts the Asia/Kolkata fractional-offset zone" do
      patch settings_time_zone_path, params: { time_zone: "Asia/Kolkata" }

      expect(response).to redirect_to(settings_path)
      expect(user.reload.time_zone).to eq("Asia/Kolkata")
    end

    it "rejects an unknown zone with an alert and no DB change" do
      original = user.reload.time_zone
      patch settings_time_zone_path, params: { time_zone: "Mars/Olympus_Mons" }

      expect(response).to redirect_to(settings_path)
      expect(flash[:alert]).to be_present
      expect(user.reload.time_zone).to eq(original)
    end

    it "rejects a blank zone" do
      original = user.reload.time_zone
      patch settings_time_zone_path, params: { time_zone: "" }

      expect(response).to redirect_to(settings_path)
      expect(flash[:alert]).to be_present
      expect(user.reload.time_zone).to eq(original)
    end
  end

  describe "PATCH /settings/time_zone (JSON / detect caller)" do
    it "returns 204 on a valid update" do
      patch settings_time_zone_path,
            params: { time_zone: "America/Los_Angeles" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(user.reload.time_zone).to eq("America/Los_Angeles")
    end

    it "returns 422 on an unknown zone with no DB change" do
      original = user.reload.time_zone

      patch settings_time_zone_path,
            params: { time_zone: "Garbage/NotReal" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.time_zone).to eq(original)
    end

    it "returns 422 on a blank zone with no DB change" do
      original = user.reload.time_zone

      patch settings_time_zone_path,
            params: { time_zone: "" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.time_zone).to eq(original)
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces to /login without touching anything" do
      patch settings_time_zone_path, params: { time_zone: "Europe/Bucharest" }

      expect(response).to redirect_to(login_path)
    end
  end

  describe "friendly URL" do
    it "preserves /settings/time_zone (no numeric / UUID id surface)" do
      # The route helper must produce the friendly path verbatim.
      expect(settings_time_zone_path).to eq("/settings/time_zone")
    end
  end

  describe "yes / no boundary sweep" do
    # The tz update flow does not carry an external Boolean — the
    # only payload is the zone string. This spec is the rule-sweep
    # backstop: assert no Boolean leaks into the wire shape.
    it "does not accept or echo a Boolean field" do
      patch settings_time_zone_path,
            params: { time_zone: "UTC", enabled: true }
      expect(response.body).not_to include("true")
      expect(response.body).not_to include("false")
    end
  end
end
