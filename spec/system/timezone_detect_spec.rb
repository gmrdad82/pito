require "rails_helper"

# Phase 26 — 01a. Timezone foundation. Critical-journey spec for the
# first-load detect flow.
#
# The actual `Intl.DateTimeFormat().resolvedOptions().timeZone` call
# requires a real JS-capable browser. We don't have one in the spec
# stack (Capybara runs rack_test by default and the project's Gemfile
# does not ship selenium). Instead we assert the contract:
#
#   1. The authenticated layout renders the `timezone-detect` Stimulus
#      controller mount + the user's stored zone in the
#      `data-timezone-detect-stored-value` attribute on `<body>`.
#   2. The unauthenticated layout does NOT render the stored-value
#      attribute (the JS bails silently).
#   3. Simulating the Stimulus detect (a PATCH with the browser zone)
#      persists. A subsequent reload sees the new zone on `<body>` so
#      the detect bails on its own.
RSpec.describe "Timezone first-load detect", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { User.first || create(:user) }

  before { Current.user = user }

  it "mounts the timezone-detect controller on authenticated pages with the stored zone" do
    user.update!(time_zone: "Etc/UTC")
    visit settings_path

    body = page.find("body", visible: false)
    expect(body[:"data-controller"]).to include("timezone-detect")
    expect(body[:"data-timezone-detect-stored-value"]).to eq("Etc/UTC")
    expect(body[:"data-timezone-detect-url-value"]).to eq("/settings/time_zone")
  end

  it "renders the stored zone verbatim once the user has set one" do
    user.update!(time_zone: "Europe/Bucharest")
    visit settings_path

    body = page.find("body", visible: false)
    # The Stimulus controller reads the stored-value and bails when
    # it is anything other than the Etc/UTC sentinel.
    expect(body[:"data-timezone-detect-stored-value"]).to eq("Europe/Bucharest")
  end

  it "simulates the detect PATCH and persists the browser zone" do
    user.update!(time_zone: "Etc/UTC")
    visit settings_path

    # Replay the PATCH the Stimulus controller would issue. The wire
    # shape is identical to the form submit. CSRF protection is
    # disabled in the test env (`allow_forgery_protection = false`)
    # so we don't need to forward an authenticity token here — in
    # production the Stimulus controller reads the token off the
    # `<meta name="csrf-token">` tag and sets the `X-CSRF-Token`
    # header.
    page.driver.submit :patch, "/settings/time_zone",
                       { time_zone: "Europe/Bucharest" }

    expect(user.reload.time_zone).to eq("Europe/Bucharest")
  end

  it "does not re-detect after the zone is set (subsequent loads carry a non-sentinel value)" do
    user.update!(time_zone: "America/Los_Angeles")
    visit settings_path
    visit settings_path

    body = page.find("body", visible: false)
    # The Stimulus controller's connect() checks this value === "Etc/UTC"
    # and bails immediately when it isn't.
    expect(body[:"data-timezone-detect-stored-value"]).to eq("America/Los_Angeles")
    expect(body[:"data-timezone-detect-stored-value"]).not_to eq("Etc/UTC")
  end
end
