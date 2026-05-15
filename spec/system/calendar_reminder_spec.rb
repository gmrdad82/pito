require "rails_helper"

# Phase 7.5 §11h — Calendar Reminder Integration (calendar-endpoint half).
#
# Unit A0 (beta-2) trimmed this spec. The channel-edit reminder-link
# rendering examples were removed when the channel became a read-only
# mirror — the `/channels/:slug/edit` form, the `[remind me on
# YYYY-MM-DD]` affordance, and the `reminder-link` Stimulus controller
# were all deleted. What survives is the calendar-side contract: the
# `POST /calendar/entries.json` endpoint that the reminder flow (and
# any other client) posts against. That endpoint is unrelated to the
# channel edit form and stays fully covered here.
#
# The rack_test driver does NOT execute JavaScript; these examples
# exercise the JSON endpoint directly via `page.driver.post`.
#
# Per CLAUDE.md hard rule: no `confirm` / `alert` / `prompt` /
# `data-turbo-confirm` introduced.
RSpec.describe "Calendar reminder (calendar entries endpoint)", type: :system do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           title: "Cached title",
           description: "desc",
           youtube_connection: connection)
  end

  before do
    driven_by(:rack_test)
    # `title_changed_at` is a kept cached column; the reminder date is
    # derived from it (the 14-day-after-change unlock convention).
    channel.update_columns(title_changed_at: 3.days.ago)
  end

  describe "POST /calendar/entries.json (Stimulus controller contract)" do
    let(:unlock_date) { (channel.title_changed_at + 14.days).to_date.iso8601 }
    # Channel-id intentionally omitted — the cross-reference validator
    # forbids `channel_id` on every user-creatable entry_type. The link
    # back to the channel lives in the title body. See
    # `app/validators/calendar_entry_cross_reference_validator.rb`.
    let(:payload) do
      {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "Channel title unlock — Cached title",
          starts_at: unlock_date,
          all_day: "yes",
          timezone: "UTC"
        }
      }
    end

    it "happy: creates a calendar entry and returns 201 with the canonical envelope" do
      expect {
        page.driver.post "/calendar/entries.json", payload.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.to change(CalendarEntry, :count).by(1), -> {
        "expected create; got #{page.driver.status_code}: #{page.driver.response.body}"
      }

      expect(page.driver.status_code).to eq(201)
      body = JSON.parse(page.driver.response.body)
      expect(body["entry"]["entry_type"]).to eq("milestone_manual")
      expect(body["entry"]["title"]).to eq("Channel title unlock — Cached title")
      expect(body["entry"]["all_day"]).to eq("yes")
      expect(body["duplicate"]).to be_nil

      ce = CalendarEntry.last
      expect(ce.entry_type).to eq("milestone_manual")
      expect(ce.title).to eq("Channel title unlock — Cached title")
      expect(ce.all_day).to eq(true)
      expect(ce.starts_at.to_date.iso8601).to eq(unlock_date)
    end

    it "edge: duplicate POST is a no-op and surfaces duplicate:'yes'" do
      page.driver.post "/calendar/entries.json", payload.to_json,
                       "CONTENT_TYPE" => "application/json"
      expect(page.driver.status_code).to eq(201)
      expect(CalendarEntry.where(title: payload[:calendar_entry][:title]).count).to eq(1)

      expect {
        page.driver.post "/calendar/entries.json", payload.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.not_to change(CalendarEntry, :count)

      expect(page.driver.status_code).to eq(200)
      body = JSON.parse(page.driver.response.body)
      expect(body["duplicate"]).to eq("yes")
      expect(body["entry"]["id"]).to eq(CalendarEntry.last.id)
      expect(CalendarEntry.where(title: payload[:calendar_entry][:title]).count).to eq(1)
    end

    it "edge: a reminder for a different unlock-date is NOT treated as a duplicate" do
      page.driver.post "/calendar/entries.json", payload.to_json,
                       "CONTENT_TYPE" => "application/json"
      expect(page.driver.status_code).to eq(201)

      other = payload.deep_dup
      other[:calendar_entry][:starts_at] = (channel.title_changed_at + 14.days + 1.day).to_date.iso8601
      expect {
        page.driver.post "/calendar/entries.json", other.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.to change(CalendarEntry, :count).by(1)
      expect(page.driver.status_code).to eq(201)
    end

    it "edge: a reminder with a different title (handle-gate variant) is NOT treated as a duplicate" do
      page.driver.post "/calendar/entries.json", payload.to_json,
                       "CONTENT_TYPE" => "application/json"

      handle_variant = payload.deep_dup
      handle_variant[:calendar_entry][:title] = "Channel handle unlock — Cached title"
      expect {
        page.driver.post "/calendar/entries.json", handle_variant.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.to change(CalendarEntry, :count).by(1)
    end

    it "sad: invalid yes/no value on all_day returns 4xx and creates no row" do
      bad = payload.deep_dup
      bad[:calendar_entry][:all_day] = "true"
      expect {
        page.driver.post "/calendar/entries.json", bad.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.not_to change(CalendarEntry, :count)
      expect(page.driver.status_code).to be_between(400, 499)
    end

    it "sad: missing entry_type returns 4xx and creates no row" do
      bad = payload.deep_dup
      bad[:calendar_entry].delete(:entry_type)
      expect {
        page.driver.post "/calendar/entries.json", bad.to_json,
                         "CONTENT_TYPE" => "application/json"
      }.not_to change(CalendarEntry, :count)
      expect(page.driver.status_code).to be_between(400, 499)
    end
  end
end
