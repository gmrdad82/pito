require "rails_helper"

# Phase 29 (settings refactor) — the install-level time zone pane was
# dropped from /settings (it lived inside the dropped Workspaces row).
# Per-user time zone is still a thing — the `/settings/time_zone` PATCH
# route survives so the existing `timezone-detect` Stimulus controller
# can write the browser-detected zone to the user row on first load.
#
# Only the "the dropdown is gone" assertion needs a system spec; the
# PATCH route is covered by a request spec elsewhere
# (`spec/requests/settings/time_zone_spec.rb` in the suite). This
# system spec just locks the negative-guard contract for the UI.
RSpec.describe "Settings → time zone pane (dropped)", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { User.first || create(:user) }

  before do
    Current.user = user
  end

  it "does NOT render the install-level time zone dropdown on /settings" do
    visit settings_path
    expect(page).not_to have_select("settings_time_zone")
    expect(page).not_to have_css("h2", text: "time zone")
  end

  it "does NOT render a time-zone form action targeting /settings/time_zone" do
    visit settings_path
    expect(page.body).not_to include('action="/settings/time_zone"')
  end
end
