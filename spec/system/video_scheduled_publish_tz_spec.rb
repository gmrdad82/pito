require "rails_helper"

# Phase 26 — 01h. Critical-journey system spec for the scheduled-
# publish picker.
#
# Contract:
#   - The picker label declares the user's stored tz.
#   - The submitted user-local instant is converted to UTC at storage.
#   - Re-rendering the picker shows the same user-local clock.
#   - Changing the user's tz between schedule + render shows the SAME
#     stored UTC instant in the NEW tz.
#   - DST spring-forward gaps are rejected with the friendly error.
#
# rack_test driver is sufficient — the modal is a plain HTML form
# submit through the Turbo Frame target.
RSpec.describe "Video scheduled-publish tz wiring", type: :system do
  before { driven_by(:rack_test) }

  # `@auto_signed_in_user` is set by spec/support/auth.rb's
  # `before(:each, type: :system)` hook BEFORE the let-bound `user`
  # is invoked. Resolving through that gives us the same user the
  # rack_test cookie is signed against — flipping `time_zone` on
  # that user actually changes the picker the controller sees.
  let(:user) { @auto_signed_in_user }
  let!(:connection) { create(:youtube_connection, user: user) }
  let!(:channel) { create(:channel, youtube_connection: connection) }

  let(:complete_params) do
    {
      pre_publish_game_ok: "yes",
      pre_publish_age_ok: "yes",
      pre_publish_paid_promotion_ok: "yes",
      pre_publish_end_screen_ok: "yes"
    }
  end

  it "renders the picker label with the user's stored zone" do
    user.update!(time_zone: "Europe/Bucharest")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    visit pre_publish_checklist_video_path(video, target_action: "schedule")

    expect(page).to have_field("video_publish_at")
    expect(page).to have_css('input[data-tz="Europe/Bucharest"]')
    expect(page).to have_content("publish at (Europe/Bucharest)")
  end

  it "stores the user-local clock as UTC and re-renders the same local clock" do
    user.update!(time_zone: "Europe/Bucharest")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    # Pick a publish at 2026-06-01 09:00 in Europe/Bucharest (DST,
    # UTC+3) → stored as 2026-06-01 06:00 UTC.
    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-06-01T09:00") }

    video.reload
    expect(video.publish_at.utc).to eq(Time.utc(2026, 6, 1, 6, 0, 0))

    # Re-render the picker — the value attribute reflects the same
    # user-local clock the user picked.
    visit pre_publish_checklist_video_path(video, target_action: "schedule")
    input = page.find("input#video_publish_at", visible: :all)
    expect(input.value).to eq("2026-06-01T09:00")
  end

  it "renders the same stored UTC instant in a NEW zone when the user moves" do
    user.update!(time_zone: "Europe/Bucharest")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-06-01T09:00") }

    # The user moves to LA.
    user.update!(time_zone: "America/Los_Angeles")
    visit pre_publish_checklist_video_path(video, target_action: "schedule")

    # Bucharest 09:00 (UTC+3) == 06:00 UTC. In LA (UTC-7, DST), that
    # renders as 2026-05-31T23:00.
    input = page.find("input#video_publish_at", visible: :all)
    expect(input.value).to eq("2026-05-31T23:00")
    expect(page).to have_content("publish at (America/Los_Angeles)")
  end

  it "stores the correct UTC instant for a UTC+5:30 user (Asia/Kolkata)" do
    user.update!(time_zone: "Asia/Kolkata")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    # 12:00 Kolkata == 06:30 UTC.
    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-06-01T12:00") }

    expect(video.reload.publish_at.utc).to eq(Time.utc(2026, 6, 1, 6, 30, 0))
  end

  it "stores the correct UTC instant for a UTC+14 user (Pacific/Kiritimati)" do
    user.update!(time_zone: "Pacific/Kiritimati")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    # 14:00 Kiritimati == 00:00 UTC same day.
    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-06-01T14:00") }

    expect(video.reload.publish_at.utc).to eq(Time.utc(2026, 6, 1, 0, 0, 0))
  end

  it "rejects a DST spring-forward gap (America/Los_Angeles 2026-03-08 02:30)" do
    user.update!(time_zone: "America/Los_Angeles")
    video = create(:video, channel: channel, title: "ok", category_id: "20")

    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-03-08T02:30") }

    expect(video.reload.publish_at).to be_nil
    expect(page).to have_content("does not exist due to DST spring-forward")
  end

  it "renders the scheduled-for display in the user's stored zone (edit form)" do
    user.update!(time_zone: "Europe/Bucharest")
    video = create(:video, channel: channel, title: "ok", category_id: "20")
    page.driver.submit :patch,
                       schedule_video_path(video),
                       { video: complete_params.merge(publish_at: "2026-06-01T09:00") }

    visit edit_video_path(video)
    # `l_user_tz` :long format renders `Jun 1, 2026 09:00 EEST`.
    expect(page).to have_content("scheduled for:")
    expect(page).to have_content("Jun 1, 2026 09:00")
  end
end
