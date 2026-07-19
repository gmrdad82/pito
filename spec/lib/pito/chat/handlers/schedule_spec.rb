# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Schedule do
  include ActiveSupport::Testing::TimeHelpers
  # All paths use the real lexer+parser so that token types (number, colon,
  # unknown "-") match what the handler's date-detection logic expects.
  def schedule_real(input)
    msg = Pito::Chat::Parser.call(
      Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
    )
    described_class.new(message: msg, conversation: Conversation.singleton).call
  end

  let!(:channel) { create(:channel) }
  # Private + never-published — the realistic pre-schedule state. YouTube's own
  # status.publishAt constraint (Video#already_published?) refuses a vid that
  # has ever gone public, so an ALREADY-public fixture here would silently
  # model the exact 2026-07-19 production bug instead of the happy path; that
  # scenario gets its own dedicated context below.
  let!(:video)   { create(:video, channel: channel, title: "Episode One", privacy_status: :private, publish_at: nil) }

  # ── Happy paths ───────────────────────────────────────────────────────────────

  it "emits a :confirmation event when given DD-MM-YYYY HH:MM" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "emits a :confirmation event when given DD-MM-YYYY only" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "does NOT update the video directly" do
    schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(video.reload.privacy_status).to eq("private")
    expect(video.reload.publish_at).to be_nil
  end

  it "carries command video_schedule in the confirmation payload" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result.events.first[:payload]["command"]).to eq("video_schedule")
  end

  it "carries publish_at as an ISO8601 string in the confirmation payload" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    payload = result.events.first[:payload]
    expect(payload["publish_at"]).to be_present
    expect { Time.iso8601(payload["publish_at"]) }.not_to raise_error
  end

  it "includes the video title in the confirmation body" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result.events.first[:payload]["body"]).to include("Episode One")
  end

  it "resolves by bare id" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves by #id" do
    result = schedule_real("schedule video ##{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves with plural noun filler 'videos'" do
    result = schedule_real("schedule videos #{video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "parses the date as app-local zone and stores UTC in publish_at" do
    travel_to Time.zone.local(2026, 6, 9, 10, 0) do
      result = schedule_real("schedule video #{video.id} 16-06-2026 12:00")
      payload = result.events.first[:payload]
      expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 16, 12, 0).utc.iso8601)
    end
  end

  # ── Error paths ───────────────────────────────────────────────────────────────

  it "returns a usage hint when no reference is given" do
    # Just the verb with no body
    msg = Pito::Chat::Message.new(tool: :schedule, body_tokens: [], kind: :new_turn, raw: "schedule")
    result = described_class.new(message: msg, conversation: Conversation.singleton).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.needs_ref")
  end

  it "returns a bad_when error for an unparseable date string" do
    result = schedule_real("schedule video #{video.id} next-tuesday")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.bad_when")
  end

  it "returns a bad_when error for a calendrically invalid date (month 99)" do
    result = schedule_real("schedule video #{video.id} 01-99-2025")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.bad_when")
  end

  it "returns a witty in-past error for a past date" do
    result = schedule_real("schedule video #{video.id} 01-01-2020")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("Episode One")
  end

  it "returns too_soon error for a time less than 30 minutes from now" do
    soon = 10.minutes.from_now
    result = schedule_real("schedule video #{video.id} #{soon.strftime('%d-%m-%Y %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.too_soon")
  end

  it "emits a confirmation for a time exactly 30 minutes from now (boundary)" do
    # 31 minutes to be safely above the 30m threshold regardless of execution timing
    future = 31.minutes.from_now
    result = schedule_real("schedule video #{video.id} #{future.strftime('%d-%m-%Y %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "returns a witty not-found for an unknown video reference" do
    result = schedule_real("schedule video 999999 #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result.events.first[:payload]["text"]).to include("999999")
  end

  it "returns not-found for a title reference (id-only resolution)" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%d-%m-%Y')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:system)
  end

  context "confirmation body displays time in the house date format" do
    it "includes the house-formatted date in the body" do
      travel_to Time.zone.local(2026, 6, 9, 10, 0) do
        result = schedule_real("schedule video #{video.id} 16-06-2026 15:30")
        body = result.events.first[:payload]["body"]
        expect(body).to include("16 Jun 15:30")
      end
    end

    it "collapses to bare HH:MM when the scheduled date IS today" do
      travel_to Time.zone.local(2026, 6, 9, 10, 0) do
        result = schedule_real("schedule video #{video.id} 09-06-2026 15:30")
        body = result.events.first[:payload]["body"]
        expect(body).to include("15:30")
        expect(body).not_to include("09-06-2026")
      end
    end
  end

  # ── State-guard edge cases ────────────────────────────────────────────────────
  # The handler does not gate on channel connection — that's enforced at the
  # job level (VideoRemoteStatusSync). It DOES gate on one piece of video
  # state: whether the vid has already gone public on YouTube (see the
  # "already published on YouTube" context below) — that one is YouTube's own
  # status.publishAt constraint, not an app-level connection concern.

  context "state-guard: handler does not gate on video state or channel connection" do
    it "emits :confirmation for an already-private video (privacy_status: :private, publish_at: nil)" do
      private_video = create(:video, channel: channel, title: "Private Ep",
                              privacy_status: :private, publish_at: nil)
      result = schedule_real("schedule video #{private_video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits :confirmation for a reschedule and payload publish_at carries the NEW time" do
      # Video already has a publish_at; scheduling to a different absolute date
      # must update the confirmation payload to the new time, not the old one.
      travel_to Time.zone.local(2026, 6, 19, 10, 0) do
        already_scheduled = create(:video, channel: channel, title: "Already Scheduled",
                                   privacy_status: :private, publish_at: 3.days.from_now)
        result = schedule_real("schedule video #{already_scheduled.id} 25-06-2026 14:00")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:confirmation)
        payload = result.events.first[:payload]
        expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 25, 14, 0).utc.iso8601)
      end
    end

    it "emits :confirmation when the video's channel has no youtube_connection" do
      # :channel factory never attaches youtube_connection by default — only
      # the :on_connection trait does. The handler must not gate on this.
      # privacy_status: :private isolates the concern under test (connection
      # state) from the already-published guard exercised separately below.
      disconnected_channel = create(:channel)
      disconnected_video = create(:video, channel: disconnected_channel, title: "No Connection Vid",
                                  privacy_status: :private, publish_at: nil)
      result = schedule_real("schedule video #{disconnected_video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end
  end

  # ── Already-published guard (root cause of the 2026-07-19 invalidPublishAt
  # production incident) ────────────────────────────────────────────────────
  # YouTube's status.publishAt: "This property can only be set if the video's
  # privacy status is private and the video has never been published"
  # (developers.google.com/youtube/v3/docs/videos). A vid that is CURRENTLY
  # public on YouTube has already been published — pairing privacyStatus:
  # private with publishAt in the SAME PUT does not satisfy the "never
  # published" half, so YouTube still rejects it. This is the failure that a
  # `privacy_status: :public` fixture on the schedule handler would have
  # silently modeled as a success before this guard existed.

  context "already published on YouTube" do
    let!(:published_video) do
      create(:video, channel: channel, title: "Live Already", privacy_status: :public, publish_at: nil)
    end

    it "does NOT emit a :confirmation event" do
      result = schedule_real("schedule video #{published_video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "names the video in a schedule_already_public message" do
      result = schedule_real("schedule video #{published_video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
      text = result.events.first[:payload]["text"]
      expect(text).to include("Live Already")
    end

    it "does not mutate the video" do
      schedule_real("schedule video #{published_video.id} #{7.days.from_now.strftime('%d-%m-%Y')}")
      expect(published_video.reload.privacy_status).to eq("public")
      expect(published_video.reload.publish_at).to be_nil
    end
  end

  # ── Natural-language <when> forms ────────────────────────────────────────────
  context "natural-language <when> forms" do
    around { |example| Time.use_zone("UTC") { travel_to(Time.zone.local(2026, 6, 16, 10, 0)) { example.run } } }

    it "emits a confirmation for `in 2 hours`" do
      result = schedule_real("schedule video #{video.id} in 2 hours")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits a confirmation for `tomorrow`" do
      result = schedule_real("schedule video #{video.id} tomorrow")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits a confirmation for `tomorrow at noon`" do
      result = schedule_real("schedule video #{video.id} tomorrow at noon")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits a confirmation for `for DD.MM.YYYY HH:MM` (dot separators)" do
      result = schedule_real("schedule video #{video.id} for 20.06.2026 14:30")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "carries the local time in publish_at for `at 2pm`" do
      result = schedule_real("schedule video #{video.id} at 2pm")
      payload = result.events.first[:payload]
      expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 16, 14, 0).utc.iso8601)
    end

    it "carries the local time in publish_at for `at 15:30`" do
      result = schedule_real("schedule video #{video.id} at 15:30")
      payload = result.events.first[:payload]
      expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 16, 15, 30).utc.iso8601)
    end

    it "carries the local time in publish_at for `tomorrow at 3:10am`" do
      result = schedule_real("schedule video #{video.id} tomorrow at 3:10am")
      payload = result.events.first[:payload]
      expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 17, 3, 10).utc.iso8601)
    end

    it "returns the in-past error for `at 3:10am` that already passed today" do
      result = schedule_real("schedule video #{video.id} at 3:10am")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("Episode One")
    end

    it "returns too_soon for `in 10m` (under the 30-minute guard)" do
      result = schedule_real("schedule video #{video.id} in 10m")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.schedule.too_soon")
    end

    it "returns the in-past error for an `at <HH>` that already passed today" do
      # now is 10:00; `at 9` resolves to today 09:00, which is in the past.
      result = schedule_real("schedule video #{video.id} at 9")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("Episode One")
    end

    it "emits a confirmation for `saturday at noon` (this week's Saturday 2026-06-20 is future)" do
      result = schedule_real("schedule video #{video.id} saturday at noon")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
      payload = result.events.first[:payload]
      expect(payload["publish_at"]).to eq(Time.zone.local(2026, 6, 20, 12, 0).utc.iso8601)
    end

    it "emits a confirmation for `next monday at 14:00`" do
      result = schedule_real("schedule video #{video.id} next monday at 14:00")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits a confirmation for `next month`" do
      result = schedule_real("schedule video #{video.id} next month")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits a confirmation for `tomorrow night`" do
      result = schedule_real("schedule video #{video.id} tomorrow night")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "returns the in-past error for bare `monday` (resolves to 2026-06-15, already past)" do
      # NOW = Tue 2026-06-16 10:00; bare weekday resolves to beginning_of_week + 0 = 2026-06-15 09:00
      result = schedule_real("schedule video #{video.id} monday")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("Episode One")
    end
  end

  # ── Stage-time spacing conflict (WP2) ────────────────────────────────────────
  # The handler dry-runs the real :schedule-context validation (assign +
  # valid?(:schedule)) before building the confirmation, so a collision with
  # another scheduled video on the SAME channel (±60 min) is caught before the
  # user ever sees a confirmation prompt. Anchored to a fixed local time (not
  # *.from_now) so the DD-MM-YYYY HH:MM <when> text — which carries only
  # minute precision — lines up exactly with the fixture's publish_at; no
  # sub-minute drift near the 60-minute boundary test.
  context "stage-time spacing conflict" do
    around { |example| travel_to(Time.zone.local(2026, 6, 16, 10, 0)) { example.run } }

    let(:anchor_at) { Time.zone.local(2026, 6, 26, 15, 0) }
    let!(:anchor) do
      create(:video, channel: channel, title: "Anchor Ep", privacy_status: :private, publish_at: anchor_at)
    end

    it "emits a :system schedule_conflict event instead of :confirmation when within 60 minutes of another scheduled video" do
      result = schedule_real("schedule video #{video.id} #{(anchor_at + 20.minutes).strftime('%d-%m-%Y %H:%M')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["command"]).to be_nil
    end

    it "the conflict text names both the staged video and the colliding video" do
      result = schedule_real("schedule video #{video.id} #{(anchor_at + 20.minutes).strftime('%d-%m-%Y %H:%M')}")
      text = result.events.first[:payload]["text"]
      expect(text).to include("Episode One")
      expect(text).to include("Anchor Ep")
    end

    it "does NOT mutate the video — the dry-run assignment is restored, not persisted" do
      schedule_real("schedule video #{video.id} #{(anchor_at + 20.minutes).strftime('%d-%m-%Y %H:%M')}")
      expect(video.reload.privacy_status).to eq("private")
      expect(video.reload.publish_at).to be_nil
    end

    it "is valid at exactly 60 minutes away (boundary — emits :confirmation, not a conflict)" do
      result = schedule_real("schedule video #{video.id} #{(anchor_at + 60.minutes).strftime('%d-%m-%Y %H:%M')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "a colliding time on a DIFFERENT channel is not a conflict" do
      other_channel = create(:channel)
      other_video = create(:video, channel: other_channel, title: "Other Channel Ep")
      result = schedule_real("schedule video #{other_video.id} #{(anchor_at + 10.minutes).strftime('%d-%m-%Y %H:%M')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end
  end

  # ── slate: the upcoming-schedule planning view ────────────────────────────────

  describe "schedule <id> slate" do
    it "renders the upcoming-schedule view (a :system vid list), not a confirmation" do
      create(:video, channel:, privacy_status: :private, publish_at: 2.days.from_now, title: "Next Up")
      result = schedule_real("schedule #{video.id} slate")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["reply_target"]).to eq("video_list")
      expect(event[:payload]["table_rows"].size).to eq(1)
    end

    it "excludes the reference vid from its own slate" do
      video.update!(privacy_status: :private, publish_at: 2.days.from_now)
      result = schedule_real("schedule #{video.id} slate")

      # The ref vid is the only scheduled one and is excluded → empty week copy.
      expect(result.events.first[:payload]["text"]).to be_present
      expect(result.events.first[:payload]["table_rows"]).to be_nil
    end

    it "filters to `only @handles` (union), overriding the shift+tab scope" do
      mine   = create(:channel, handle: "@mine")
      theirs = create(:channel, handle: "@theirs")
      create(:video, channel: mine,   privacy_status: :private, publish_at: 2.days.from_now, title: "Mine")
      create(:video, channel: theirs, privacy_status: :private, publish_at: 2.days.from_now, title: "Theirs")

      result = schedule_real("schedule #{video.id} slate only @mine")
      titles = result.events.first[:payload]["table_rows"].map { |r| r[:cells][1][:text] }
      expect(titles).to eq(%w[Mine])
    end
  end
end
