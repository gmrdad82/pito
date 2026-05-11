require "rails_helper"

# Phase 7.5 §11h — Calendar Reminder Integration.
#
# Stimulus-controller-mediated wiring between the 14-day title/handle
# unlock gate on `/channels/:slug/edit` and the Phase 21 JSON endpoint
# `POST /calendar/entries.json`. The rack_test driver does NOT execute
# JavaScript, so the system spec covers what is testable end-to-end:
#
#   1. The edit page renders the `[remind me on YYYY-MM-DD]` link with
#      every data attribute the Stimulus controller reads
#      (`reminder_link_*_value`, including the new `channel_name` and
#      `timezone` values added in 11h).
#   2. POSTing the exact JSON payload the Stimulus controller builds
#      against `/calendar/entries.json` succeeds — happy path.
#   3. The same payload posted twice is idempotent — a duplicate
#      reminder for the same (channel, title, date) tuple is a no-op
#      and surfaces the `duplicate: "yes"` marker rather than
#      creating a second row.
#   4. A bad payload (invalid yes/no, missing starts_at) returns 4xx
#      and creates no row — the form on the other side stays usable.
#
# Per CLAUDE.md hard rule: no `confirm` / `alert` / `prompt` /
# `data-turbo-confirm` introduced. Toast is a passive flash.
RSpec.describe "Calendar reminder (channel 14-day gate)", type: :system do
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
    # The title gate is open when title_changed_at is strictly within
    # the 14-day window. Backdate to 3 days ago so the gate locks and
    # the [remind me] link renders.
    channel.update_columns(title_changed_at: 3.days.ago)
  end

  describe "[remind me on YYYY-MM-DD] link rendering" do
    it "happy path: renders the link with every data attribute the controller reads" do
      visit edit_channel_path(channel)

      expect(page).to have_content("edit channel")
      expect(page).to have_css('a[data-controller="reminder-link"]')

      link = find('a[data-controller="reminder-link"]')
      expected_date = (channel.title_changed_at + 14.days).to_date.iso8601
      expect(link.text).to include("[remind me on #{expected_date}]")
      expect(link["data-reminder-link-unlock-date-value"]).to eq(expected_date)
      expect(link["data-reminder-link-field-value"]).to eq("title")
      expect(link["data-reminder-link-channel-id-value"]).to eq(channel.id.to_s)
      expect(link["data-reminder-link-channel-name-value"]).to eq("Cached title")
      expect(link["data-reminder-link-timezone-value"]).to be_present
    end

    it "falls back to the channel URL slug when Channel#title is blank" do
      channel.update_columns(title: nil)
      visit edit_channel_path(channel)
      link = find('a[data-controller="reminder-link"]')
      expect(link["data-reminder-link-channel-name-value"]).to eq("UCabcabcabcabcabcabcabcA")
    end

    it "renders the handle-gate link with field=handle when the handle gate is open" do
      channel.update_columns(
        title_changed_at: nil,
        handle: "@x",
        handle_changed_at: 1.day.ago
      )
      visit edit_channel_path(channel)
      link = find('a[data-controller="reminder-link"]')
      expect(link["data-reminder-link-field-value"]).to eq("handle")
    end

    it "omits the link when the gate is NOT locked (field is currently editable)" do
      channel.update_columns(title_changed_at: 20.days.ago)
      visit edit_channel_path(channel)
      expect(page).to have_no_css('a[data-controller="reminder-link"]')
      expect(page).to have_field("channel[title]")
    end

    it "escapes a channel title containing markup (XSS smoke)" do
      channel.update_columns(title: '<script>alert("x")</script>')
      visit edit_channel_path(channel)
      link = find('a[data-controller="reminder-link"]')
      # `data-*` attributes are surfaced as plain strings — angle brackets
      # are NOT executed as DOM nodes, and Capybara's `[…]` accessor
      # returns the decoded text. The page source must not contain a
      # live `<script>` injection inside the attribute value.
      expect(link["data-reminder-link-channel-name-value"]).to eq('<script>alert("x")</script>')
      raw = page.html
      expect(raw).to include("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;")
      expect(raw).not_to match(%r{<script>alert\("x"\)</script>})
    end
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
