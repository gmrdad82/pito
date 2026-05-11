require "rails_helper"

# Phase 26 — 01a. Timezone foundation. Critical-journey system spec
# for the Settings dropdown pane — the user picks a zone, hits
# `[update]`, the page reloads, and the stored zone is persisted.
#
# rack_test driver is sufficient — the dropdown is a plain HTML form
# submit. The Stimulus detect flow has its own dedicated spec
# (`timezone_detect_spec.rb`).
RSpec.describe "Settings → time zone pane", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { User.first || create(:user) }

  before do
    Current.user = user
  end

  it "renders the pane with the user's current zone pre-selected" do
    user.update!(time_zone: "Etc/UTC")
    visit settings_path

    expect(page).to have_content("time zone")
    expect(page).to have_content("your time zone")
    # The dropdown carries every Rails zone — assert a couple of
    # canonical names are present.
    expect(page).to have_select("settings_time_zone")
    expect(page).to have_css("option[value='Europe/Bucharest']")
    expect(page).to have_css("option[value='America/Los_Angeles']")
    expect(page).to have_css("option[value='Asia/Kolkata']")
    expect(page).to have_css("option[value='Pacific/Kiritimati']")
    # Current zone (Etc/UTC) is selected.
    expect(page).to have_css("option[selected][value='Etc/UTC']")
  end

  it "persists a new zone when the user submits the form" do
    user.update!(time_zone: "Etc/UTC")
    visit settings_path

    # Scope the click to the time-zone form — `[update]` appears on
    # several Settings forms.
    within "form[action='#{settings_time_zone_path}']" do
      select "(GMT+02:00) Bucharest", from: "settings_time_zone"
      click_button "[update]"
    end

    expect(page).to have_current_path(settings_path)
    expect(page).to have_content("time zone saved.")
    expect(user.reload.time_zone).to eq("Europe/Bucharest")
  end

  it "pre-selects the persisted zone on a reload" do
    user.update!(time_zone: "America/Los_Angeles")
    visit settings_path

    expect(page).to have_css("option[selected][value='America/Los_Angeles']")
  end

  it "supports the Pacific/Kiritimati UTC+14 edge zone end-to-end" do
    user.update!(time_zone: "Etc/UTC")
    visit settings_path

    # `Pacific/Kiritimati` lives in the "all IANA" optgroup (Rails's
    # curated `TimeZone.all` does NOT include it). The label is the
    # bare IANA name there.
    within "form[action='#{settings_time_zone_path}']" do
      select "Pacific/Kiritimati", from: "settings_time_zone"
      click_button "[update]"
    end

    expect(user.reload.time_zone).to eq("Pacific/Kiritimati")
  end
end
