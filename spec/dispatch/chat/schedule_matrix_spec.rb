# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `schedule` (recognition only, DB mocked) ────────────────────
#
# RULE: every kwarg combination is recognised — no exception. We test what the
# handler UNDERSTANDS, not data persistence. All DB lookups are stubbed.
#
# Subject: Pito::Chat::Handlers::Schedule
#          (lib/pito/chat/handlers/schedule.rb)
#          Pito::Schedule::TimeParser
#          (app/services/pito/schedule/time_parser.rb)
#
# Handler resolution path:
#   1. Strip NOUN_FILLERS (%w[vid vids video videos]) from body_tokens.
#   2. If body empty → needs_ref.
#   3. If body.last == "slate" → slate planning path.
#   4. TimeParser.call(body) — splits at the longest trailing <when> phrase.
#      Returns nil if no phrase matches → bad_when error.
#   5. ref = leading tokens before the <when> phrase, joined.
#   6. If ref blank → needs_ref.
#   7. resolve_video(ref) → strips leading `#`, requires /\A\d+\z/, find_by(id:).
#      If nil → :system event (not_found).
#   8. If publish_time <= Time.current → :system event (schedule_in_past).
#   9. If publish_time < 30.minutes.from_now → Result::Error (too_soon).
#  10. → :confirmation event (video_schedule).
#
# TimeParser supported <when> grammar (exhaustive; all forms exercised below):
#
#   in N m|min|minutes               → Time.current + N minutes
#   in N h|hr|hour[s]                → Time.current + N hours
#   in N day[s]                      → that calendar date at 09:00 local
#   in N h [from now]                → same as above with optional suffix
#   at noon|midnight|night|Npm|HH:MM → today at that time
#   today [[at] <tod>]               → today (bare → 09:00)
#   tomorrow [[at] <tod>]            → tomorrow
#   <weekday> [[at] <tod>]           → that weekday this calendar week
#   next <weekday> [[at] <tod>]      → that weekday next calendar week
#   next week [[at] <tod>]           → Monday of next week
#   next month [[at] <tod>]          → 1st of next month
#   N days from now [[at] <tod>]     → relative calendar date
#   N weeks from now [[at] <tod>]    → relative calendar date
#   [for] DD.MM.YYYY [HH:MM]         → absolute date (. sep)
#   [for] DD-MM-YYYY [HH:MM]         → absolute date (- sep)
#
# Follow-up contract (Batch-3 lesson):
#   `schedule` IS declared in video_list's actions — follow-up via video_list is valid.
#   `schedule` is NOT in video_detail's actions — not reachable from a detail card.
#
# All DB mocked; TimeParser is pure (not mocked).

RSpec.describe "Dispatch matrix — schedule (recognition, DB mocked)", type: :dispatch do
  include ActiveSupport::Testing::TimeHelpers

  # Fixed instant: Tuesday 2026-06-16 10:00:00 UTC (DST-free, same as time_parser_spec).
  # Week: Mon 2026-06-15 … Sun 2026-06-21.  Next week: Mon 2026-06-22 … Sun 2026-06-28.
  SCHED_NOW = Time.find_zone("UTC").local(2026, 6, 16, 10, 0).freeze

  SCHED_STUB_ID = 42

  let(:video_double) { double("Video", id: SCHED_STUB_ID, title: "Test Video") }
  let(:conversation) { double("Conversation") }

  around do |example|
    Time.use_zone("UTC") { travel_to(SCHED_NOW) { example.run } }
  end

  before do
    # Avoid the Conversation#events DB query inside Pito::HandleGenerator.
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-1234")
    # Default: every Video.find_by succeeds.
    allow(::Video).to receive(:find_by).and_return(video_double)
    # WP2: every non-past, non-too-soon path now runs a stage-time dry-run
    # (assign_attributes + valid?(:schedule) + restore_attributes) before
    # building the confirmation. This is a recognition-only matrix — no real
    # Video rows exist, so the model's own 60-min-spacing query never runs;
    # default the dry-run to "no collision" so the existing confirmation
    # matrix is unaffected. Only the "stage-time spacing conflict" section
    # below overrides valid? to exercise the conflict branch.
    # The stage-time dry-run consults the spacing LAW directly (no more
    # assign/valid?(:schedule)/restore dance on the video) — recognition
    # examples run with a law that finds no violation.
    allow(Pito::Schedule::SpacingPolicy).to receive(:call).and_return(nil)
    # YouTube's own status.publishAt constraint (Video#already_published?):
    # default every stub vid to eligible so the existing recognition matrix
    # is unaffected. The dedicated "already published on YouTube" section
    # below overrides this to exercise the new guard.
    allow(video_double).to receive(:already_published?).and_return(false)
  end

  # Build and invoke a Schedule handler from a raw chat input string.
  # Splits on whitespace — the first word is the verb, the rest become body_tokens.
  # All tokens are marked preceded_by_space: true so TimeParser reconstruct/join
  # produces the same string as " ".join (correct for all supported <when> forms).
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..] # drop the verb token ("schedule")
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      tool:        :schedule,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Schedule.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up:).call
  end

  # Shared assertion helpers (reduce noise in the bulk matrices below).
  def expect_confirmation(result, video_id: SCHED_STUB_ID, publish_at: nil)
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:confirmation)
    expect(event[:payload]["command"]).to   eq("video_schedule")
    expect(event[:payload]["video_id"]).to  eq(video_id)
    expect(event[:payload]["publish_at"]).to eq(publish_at) if publish_at
  end

  def expect_system_past(result)
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["command"]).to be_nil
  end

  def expect_too_soon(result)
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.too_soon")
  end

  def expect_needs_ref(result)
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.needs_ref")
  end

  def expect_bad_when(result)
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.bad_when")
  end

  # ── Bare verb / noun-only → needs_ref ─────────────────────────────────────────
  #
  # After stripping NOUN_FILLERS, body is empty → needs_ref.

  describe "bare verb / noun-only (no id, no <when>) → needs_ref" do
    [
      "schedule",
      "schedule   ",
      "schedule vid",
      "schedule vids",
      "schedule video",
      "schedule videos"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error (needs_ref)" do
        expect_needs_ref(call(raw))
      end
    end
  end

  # ── Noun fillers × #id / bare-id × representative <when> → :confirmation ──────
  #
  # "tomorrow" (→ 2026-06-17 09:00, safely future) is used here as the canonical
  # <when>. The exhaustive form matrix follows below.
  # resolve_video strips `#`, then requires /\A\d+\z/, so `#5` and `5` both work.

  describe "noun fillers × #id form × tomorrow → :confirmation" do
    {
      "schedule #5 tomorrow"        => SCHED_STUB_ID,
      "schedule vid #5 tomorrow"    => SCHED_STUB_ID,
      "schedule vids #5 tomorrow"   => SCHED_STUB_ID,
      "schedule video #5 tomorrow"  => SCHED_STUB_ID,
      "schedule videos #5 tomorrow" => SCHED_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect_confirmation(result, video_id: expected_id,
                                    publish_at: "2026-06-17T09:00:00Z")
      end
    end
  end

  describe "noun fillers × bare numeric id × tomorrow → :confirmation" do
    {
      "schedule 5 tomorrow"         => SCHED_STUB_ID,
      "schedule vid 5 tomorrow"     => SCHED_STUB_ID,
      "schedule vids 5 tomorrow"    => SCHED_STUB_ID,
      "schedule video 5 tomorrow"   => SCHED_STUB_ID,
      "schedule videos 5 tomorrow"  => SCHED_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect_confirmation(result, video_id: expected_id,
                                    publish_at: "2026-06-17T09:00:00Z")
      end
    end
  end

  # ── Confirmation payload completeness ─────────────────────────────────────────

  describe "confirmation payload — full key coverage" do
    it "schedule #5 tomorrow → payload carries all expected keys" do
      result  = call("schedule #5 tomorrow")
      payload = result.events.first[:payload]
      expect(payload["command"]).to      eq("video_schedule")
      expect(payload["video_id"]).to     eq(SCHED_STUB_ID)
      expect(payload["video_title"]).to  eq("Test Video")
      expect(payload["publish_at"]).to   eq("2026-06-17T09:00:00Z")
      expect(payload["reply_handle"]).to be_present
      expect(payload["reply_target"]).to eq("confirmation")
    end
  end

  # ── Every TimeParser <when> form — exhaustive recognition matrix ───────────────
  #
  # SCHED_NOW = 2026-06-16 10:00 UTC (Tuesday).
  # Expected outcomes are annotated per row:
  #   :confirmation → :confirmation event, publish_at verified where given
  #   :system_past  → :system event (publish_time ≤ Time.current)
  #   :too_soon     → Result::Error (publish_time < 30.minutes.from_now)

  describe "relative `in …` durations (computed from Time.current)" do
    {
      # Boundary: in 30m = exactly 30.minutes.from_now → NOT too_soon (strict <)
      "in 30m"             => { outcome: :confirmation, publish_at: "2026-06-16T10:30:00Z" },
      "in 30 minutes"      => { outcome: :confirmation, publish_at: "2026-06-16T10:30:00Z" },
      "in 31m"             => { outcome: :confirmation, publish_at: "2026-06-16T10:31:00Z" },
      "in 5 min"           => { outcome: :too_soon },   # 10:05 < 10:30
      "in 10m"             => { outcome: :too_soon },   # 10:10 < 10:30
      "in 29m"             => { outcome: :too_soon },   # 10:29 < 10:30
      "in 1h"              => { outcome: :confirmation, publish_at: "2026-06-16T11:00:00Z" },
      "in 2 hours"         => { outcome: :confirmation, publish_at: "2026-06-16T12:00:00Z" },
      "in 1 hour from now" => { outcome: :confirmation, publish_at: "2026-06-16T11:00:00Z" },
      "in 3 days"          => { outcome: :confirmation, publish_at: "2026-06-19T09:00:00Z" }
    }.each do |when_phrase, expectation|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → #{expectation[:outcome]}" do
        result = call(raw)
        case expectation[:outcome]
        when :confirmation then expect_confirmation(result, publish_at: expectation[:publish_at])
        when :too_soon     then expect_too_soon(result)
        when :system_past  then expect_system_past(result)
        end
      end
    end
  end

  describe "`today` forms (bare → 09:00 = past; explicit future times → :confirmation)" do
    {
      "today"          => { outcome: :system_past },       # 09:00 < 10:00
      "today at 3am"   => { outcome: :system_past },       # 03:00 < 10:00
      "today at noon"  => { outcome: :confirmation, publish_at: "2026-06-16T12:00:00Z" },
      "today at 14:30" => { outcome: :confirmation, publish_at: "2026-06-16T14:30:00Z" },
      "today at 5pm"   => { outcome: :confirmation, publish_at: "2026-06-16T17:00:00Z" },
      "today at night" => { outcome: :confirmation, publish_at: "2026-06-16T21:00:00Z" }
    }.each do |when_phrase, expectation|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → #{expectation[:outcome]}" do
        result = call(raw)
        case expectation[:outcome]
        when :confirmation then expect_confirmation(result, publish_at: expectation[:publish_at])
        when :system_past  then expect_system_past(result)
        end
      end
    end
  end

  describe "`at <time-of-day>` forms (today-relative; NOW=10:00)" do
    {
      # Named tod tokens
      "at noon"     => { outcome: :confirmation, publish_at: "2026-06-16T12:00:00Z" },
      "at midnight" => { outcome: :system_past },      # 00:00 < 10:00
      "at night"    => { outcome: :confirmation, publish_at: "2026-06-16T21:00:00Z" },
      # 12-hour HH:MM am/pm
      "at 3:10am"   => { outcome: :system_past },      # 03:10 < 10:00
      "at 3:10pm"   => { outcome: :confirmation, publish_at: "2026-06-16T15:10:00Z" },
      "at 11pm"     => { outcome: :confirmation, publish_at: "2026-06-16T23:00:00Z" },
      "at 12am"     => { outcome: :system_past },      # midnight (00:00) < 10:00
      "at 12pm"     => { outcome: :confirmation, publish_at: "2026-06-16T12:00:00Z" },
      # 12-hour hour-only
      "at 2pm"      => { outcome: :confirmation, publish_at: "2026-06-16T14:00:00Z" },
      "at 9am"      => { outcome: :system_past },      # 09:00 < 10:00
      "at 10am"     => { outcome: :system_past },      # exactly 10:00 ≤ 10:00 → past
      "at 11am"     => { outcome: :confirmation, publish_at: "2026-06-16T11:00:00Z" },
      # 24-hour HH:MM
      "at 15:30"    => { outcome: :confirmation, publish_at: "2026-06-16T15:30:00Z" },
      "at 10:30"    => { outcome: :confirmation, publish_at: "2026-06-16T10:30:00Z" },
      "at 10:10"    => { outcome: :too_soon },         # 10:10 < 10:30
      # 24-hour hour-only
      "at 23"       => { outcome: :confirmation, publish_at: "2026-06-16T23:00:00Z" },
      "at 9"        => { outcome: :system_past }       # 09:00 < 10:00
    }.each do |when_phrase, expectation|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → #{expectation[:outcome]}" do
        result = call(raw)
        case expectation[:outcome]
        when :confirmation then expect_confirmation(result, publish_at: expectation[:publish_at])
        when :system_past  then expect_system_past(result)
        when :too_soon     then expect_too_soon(result)
        end
      end
    end
  end

  describe "`tomorrow` forms → :confirmation (all future at NOW=10:00)" do
    {
      "tomorrow"          => "2026-06-17T09:00:00Z",
      "tomorrow at noon"  => "2026-06-17T12:00:00Z",
      "tomorrow night"    => "2026-06-17T21:00:00Z",
      "tomorrow at 3:10am"  => "2026-06-17T03:10:00Z",
      "tomorrow at 14:00" => "2026-06-17T14:00:00Z",
      "tomorrow at midnight" => "2026-06-17T00:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  # Week of 2026-06-15 (Mon=15, Tue=16, Wed=17, Thu=18, Fri=19, Sat=20, Sun=21).
  # Mon 09:00 and Tue 09:00 are past (NOW=Tue 10:00). Wed onward are future.
  describe "bare weekday forms (this calendar week, Mon-first)" do
    # Full names
    {
      "monday"    => { outcome: :system_past },              # 2026-06-15 09:00
      "tuesday"   => { outcome: :system_past },              # 2026-06-16 09:00 < 10:00
      "wednesday" => { outcome: :confirmation, publish_at: "2026-06-17T09:00:00Z" },
      "thursday"  => { outcome: :confirmation, publish_at: "2026-06-18T09:00:00Z" },
      "friday"    => { outcome: :confirmation, publish_at: "2026-06-19T09:00:00Z" },
      "saturday"  => { outcome: :confirmation, publish_at: "2026-06-20T09:00:00Z" },
      "sunday"    => { outcome: :confirmation, publish_at: "2026-06-21T09:00:00Z" },
      # Common abbreviations
      "mon"       => { outcome: :system_past },
      "tue"       => { outcome: :system_past },
      "tues"      => { outcome: :system_past },
      "wed"       => { outcome: :confirmation, publish_at: "2026-06-17T09:00:00Z" },
      "thu"       => { outcome: :confirmation, publish_at: "2026-06-18T09:00:00Z" },
      "thur"      => { outcome: :confirmation, publish_at: "2026-06-18T09:00:00Z" },
      "thurs"     => { outcome: :confirmation, publish_at: "2026-06-18T09:00:00Z" },
      "fri"       => { outcome: :confirmation, publish_at: "2026-06-19T09:00:00Z" },
      "sat"       => { outcome: :confirmation, publish_at: "2026-06-20T09:00:00Z" },
      "sun"       => { outcome: :confirmation, publish_at: "2026-06-21T09:00:00Z" },
      # With time-of-day
      "saturday at noon"  => { outcome: :confirmation, publish_at: "2026-06-20T12:00:00Z" },
      "saturday night"    => { outcome: :confirmation, publish_at: "2026-06-20T21:00:00Z" }
    }.each do |when_phrase, expectation|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → #{expectation[:outcome]}" do
        result = call(raw)
        case expectation[:outcome]
        when :confirmation then expect_confirmation(result, publish_at: expectation[:publish_at])
        when :system_past  then expect_system_past(result)
        end
      end
    end
  end

  describe "`next <weekday>` forms (next calendar week, all future)" do
    # next_week returns the weekday in the NEXT calendar week (2026-06-22 to 2026-06-28).
    {
      "next monday"          => "2026-06-22T09:00:00Z",
      "next tuesday"         => "2026-06-23T09:00:00Z",
      "next wednesday"       => "2026-06-24T09:00:00Z",
      "next thursday"        => "2026-06-25T09:00:00Z",
      "next friday"          => "2026-06-26T09:00:00Z",
      "next saturday"        => "2026-06-27T09:00:00Z",
      "next sunday"          => "2026-06-28T09:00:00Z",
      # Abbreviated + time-of-day
      "next mon"             => "2026-06-22T09:00:00Z",
      "next fri"             => "2026-06-26T09:00:00Z",
      # With time-of-day clause
      "next monday at 14:00" => "2026-06-22T14:00:00Z",
      "next friday at noon"  => "2026-06-26T12:00:00Z",
      "next thursday at night" => "2026-06-25T21:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  describe "`next week` → Monday of next week" do
    {
      "next week"        => "2026-06-22T09:00:00Z",
      "next week at 10am"  => "2026-06-22T10:00:00Z",
      "next week at noon"  => "2026-06-22T12:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  describe "`next month` → 1st of next month (2026-07-01)" do
    {
      "next month"        => "2026-07-01T09:00:00Z",
      "next month at noon" => "2026-07-01T12:00:00Z",
      "next month at 6am"  => "2026-07-01T06:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  describe "`N days from now` forms (date-anchored, default 09:00)" do
    {
      "1 day from now"     => "2026-06-17T09:00:00Z",
      "4 days from now"    => "2026-06-20T09:00:00Z",
      "7 days from now"    => "2026-06-23T09:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  describe "`N weeks from now` forms (date-anchored, N×7 days from today)" do
    {
      "1 week from now"              => "2026-06-23T09:00:00Z",
      "1 week from now at 13:00"     => "2026-06-23T13:00:00Z",
      "2 weeks from now at noon"     => "2026-06-30T12:00:00Z",
      "3 weeks from now"             => "2026-07-07T09:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  describe "absolute date forms ([for] DD.MM.YYYY | DD-MM-YYYY [HH:MM])" do
    {
      # With `for` prefix, dot separator + time
      "for 20.06.2026 14:30"  => "2026-06-20T14:30:00Z",
      # With `for` prefix, hyphen separator + time
      "for 20-06-2026 14:30"  => "2026-06-20T14:30:00Z",
      # No `for`, hyphen + time
      "20-06-2026 14:30"      => "2026-06-20T14:30:00Z",
      # Date-only (default 09:00)
      "20-06-2026"            => "2026-06-20T09:00:00Z",
      "20.06.2026"            => "2026-06-20T09:00:00Z",
      # 1-digit day/month
      "5-7-2026"              => "2026-07-05T09:00:00Z"
    }.each do |when_phrase, publish_at|
      raw = "schedule 5 #{when_phrase}"
      it "#{raw.inspect} → :confirmation, publish_at: #{publish_at}" do
        expect_confirmation(call(raw), publish_at:)
      end
    end
  end

  # ── Invalid <when> → bad_when error ───────────────────────────────────────────
  #
  # TimeParser returns nil → extract_when returns :err → bad_when Result::Error.
  # Note: the video ref is still present; it's the <when> that fails to parse.

  describe "invalid / unrecognised <when> → bad_when error" do
    [
      "schedule 5",             # no <when> at all — TimeParser gets 1 token, range is empty
      "schedule 5 blah",        # free text not matching any pattern
      "schedule 5 next-tuesday", # hyphen kills next_weekday match
      "schedule 5 next blursday", # blursday not a weekday
      "schedule 5 at 25",        # hour 25 out of range for 24h
      "schedule 5 saturday at 25pm", # invalid 25pm
      "schedule 5 for 01-99-2025"   # month 99 → ArgumentError → nil
    ].each do |raw|
      it "#{raw.inspect} → Result::Error (bad_when)" do
        expect_bad_when(call(raw))
      end
    end
  end

  # ── Not-found → :system event ─────────────────────────────────────────────────

  describe "video not found → :system event" do
    before { allow(::Video).to receive(:find_by).and_return(nil) }

    {
      "schedule #99 tomorrow"    => nil,
      "schedule 99 tomorrow"     => nil,
      "schedule vid #99 tomorrow" => nil
    }.each do |raw, _|
      it "#{raw.inspect} → :system event (no command key)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end
    end

    it "non-numeric ref → nil immediately (no find_by), :system event" do
      # resolve_video returns nil for any non-digit ref — no DB call
      result = call("schedule abc tomorrow")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end
  end

  # ── Already published on YouTube → :system event (schedule_already_public) ────
  #
  # YouTube's status.publishAt: settable only on a vid that's private AND has
  # never gone public. Checked right after resolve_video, before the timing
  # gates (root cause of the 2026-07-19 invalidPublishAt production incident).

  describe "already published on YouTube → :system event" do
    before { allow(video_double).to receive(:already_published?).and_return(true) }

    it "schedule 42 tomorrow → :system event (no command key), not :confirmation" do
      result = call("schedule 42 tomorrow")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
      expect(result.events.first[:payload]["text"]).to include("Test Video")
    end
  end

  # ── Publish-time guards ────────────────────────────────────────────────────────

  describe "publish_time in the past → :system event (schedule_in_past)" do
    # These forms all produce a time ≤ NOW (2026-06-16 10:00).
    [
      "schedule 5 today",         # 2026-06-16 09:00 < 10:00
      "schedule 5 today at 3am",  # 03:00 < 10:00
      "schedule 5 monday",        # 2026-06-15 09:00 < today
      "schedule 5 tuesday",       # 2026-06-16 09:00 < 10:00
      "schedule 5 at 9am",        # today 09:00 < 10:00
      "schedule 5 at 10am"        # today 10:00 == NOW → ≤ → past
    ].each do |raw|
      it "#{raw.inspect} → :system event (past)" do
        expect_system_past(call(raw))
      end
    end
  end

  describe "publish_time < 30 minutes from now → too_soon error" do
    # 30.minutes.from_now = 10:30. Strictly less than triggers the guard.
    [
      "schedule 5 in 5 min",      # 10:05 < 10:30
      "schedule 5 in 10m",        # 10:10 < 10:30
      "schedule 5 in 29m",        # 10:29 < 10:30
      "schedule 5 at 10:10",      # 10:10 < 10:30
      "schedule 5 today at 10:10" # same
    ].each do |raw|
      it "#{raw.inspect} → Result::Error (too_soon)" do
        expect_too_soon(call(raw))
      end
    end

    it "in 30m (exactly at the boundary) is NOT too_soon → :confirmation" do
      # publish_time = 10:30, 30.minutes.from_now = 10:30.  10:30 < 10:30 = false.
      expect_confirmation(call("schedule 5 in 30m"), publish_at: "2026-06-16T10:30:00Z")
    end
  end

  # ── Stage-time spacing conflict (WP2) ─────────────────────────────────────────
  #
  # After the past/too_soon guards, the handler dry-runs the real :schedule
  # context validation (assign_attributes + valid?(:schedule)) — DB mocked, so
  # this exercises the handler's BRANCHING on valid?/publish_spacing_collision,
  # not the model's real query (that's video_spec.rb + executor_spec.rb).
  describe "stage-time spacing conflict → :system event (schedule_conflict), not :confirmation" do
    before do
      allow(Pito::Schedule::SpacingPolicy).to receive(:call).and_return(
        { kind: :spacing, title: "Collision Video", at: Time.zone.local(2026, 6, 17, 9, 30) }
      )
    end

    it "emits a :system event (no command key) instead of :confirmation" do
      result = call("schedule 5 tomorrow")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["command"]).to be_nil
    end

    it "the text names the colliding video" do
      result = call("schedule 5 tomorrow")
      expect(result.events.first[:payload]["text"]).to include("Collision Video")
    end

    it "consulted the spacing law with the staged publish time" do
      call("schedule 5 tomorrow")
      expect(Pito::Schedule::SpacingPolicy)
        .to have_received(:call).with(video: video_double, at: kind_of(Time))
    end
  end

  # ── Slate keyword → slate planner path ────────────────────────────────────────
  #
  # When the last body token (after noun-filter strip) is "slate", the handler
  # diverges to the schedule-planner path (no <when> parsing).

  describe "slate keyword → Result::Ok (slate planner path)" do
    before do
      # Stub conversation accessors called in the slate path.
      allow(conversation).to receive(:scope_channel).and_return(nil)
      allow(conversation).to receive(:stats_period).and_return("28d")
      allow(Pito::MessageBuilder::Video::Slate).to receive(:call).and_return([])
    end

    it "'schedule 5 slate' → Result::Ok (exclude id = video 5)" do
      result = call("schedule 5 slate")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "'schedule vid 5 slate' → Result::Ok (noun filler stripped, id still extracted)" do
      result = call("schedule vid 5 slate")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "'schedule slate' (body = ['slate']) → Result::Ok (no exclude id)" do
      result = call("schedule slate")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "'schedule vid slate' (noun stripped, then 'slate' only) → Result::Ok" do
      result = call("schedule vid slate")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end
  end

  # ── Follow-up via video_list AND video_detail ─────────────────────────────────
  #
  # Batch-3 rule: only assert a follow-up path if schedule is a DECLARED action
  # for that reply_target.  Check registry first; then exercise the handler.
  #
  # Phase F4: `schedule` is now a declared reply action of BOTH video_list and
  # video_detail (previously only video_list).  The registry assertions below are
  # updated accordingly.

  describe "follow-up action registry" do
    before { Pito::FollowUp::Registry.register_all! }

    it "'schedule' is declared in video_list actions" do
      expect(Pito::FollowUp::Registry.actions_for("video_list")).to include("schedule")
    end

    # Phase F4: schedule is NOW also a declared video_detail reply action.
    it "'schedule' is declared in video_detail actions" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("schedule")
    end

    it "video_detail actions are exactly the current declared verb set (incl. schedule; segment verbs G123; @ai joined the anchored-reply roster)" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail"))
        .to contain_exactly("rm", "del", "delete", "reindex", "link", "unlink",
                            "shinies", "sync", "publish", "pub", "unlist", "schedule", "analyze",
                            "game", "at-a-glance", "@ai")
    end
  end

  describe "follow-up via video_list source event" do
    # The ToolDelegator passes the full `rest` to Chat::Dispatcher as the input,
    # producing a Message where body_tokens = tokens after the verb ("schedule").
    # In the unit test we construct the handler directly with the same body_tokens.
    # The source event's `video_ids`/`table_rows` are present but the Schedule
    # handler reads only `message.body_tokens` in the non-slate path.

    let(:source_event) do
      instance_double(
        Event,
        payload: {
          "reply_target" => "video_list",
          "video_ids"    => [ SCHED_STUB_ID ],
          "table_rows"   => [
            { "cells" => [ { "text" => "##{SCHED_STUB_ID}" }, { "text" => "Test Video" } ] }
          ]
        }
      )
    end

    let(:follow_up_ctx) do
      Pito::Chat::FollowUpContext.new(
        source_event: source_event,
        rest:         "#{SCHED_STUB_ID} tomorrow"
      )
    end

    it "schedule via video_list: body_tokens carry id + when → :confirmation" do
      result = call("schedule #{SCHED_STUB_ID} tomorrow", follow_up: follow_up_ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to                eq(:confirmation)
      expect(event[:payload]["command"]).to  eq("video_schedule")
      expect(event[:payload]["video_id"]).to eq(SCHED_STUB_ID)
      expect(event[:payload]["publish_at"]).to eq("2026-06-17T09:00:00Z")
    end

    it "follow_up? is true (context carries source event)" do
      handler = make_handler("schedule #{SCHED_STUB_ID} tomorrow", follow_up: follow_up_ctx)
      expect(handler.follow_up?).to be true
    end

    it "schedule via video_list: past <when> → :system event (same guard as free-chat)" do
      result = call("schedule #{SCHED_STUB_ID} today", follow_up: follow_up_ctx)
      expect_system_past(result)
    end

    it "schedule via video_list: missing <when> → bad_when (same guard as free-chat)" do
      ctx = Pito::Chat::FollowUpContext.new(
        source_event: source_event,
        rest:         SCHED_STUB_ID.to_s
      )
      result = call("schedule #{SCHED_STUB_ID}", follow_up: ctx)
      expect_bad_when(result)
    end
  end

  # ── Follow-up via video_detail source event ───────────────────────────────────
  #
  # Phase F4 added `schedule` to video_detail's declared reply actions, so a
  # `#<handle> schedule …` reply on a detail card is GATED-IN (ToolDelegator no
  # longer rejects it) and reaches the chat Schedule handler.
  #
  # F4 FOLLOW-UP FIX — verified against source (schedule.rb#prepend_follow_up_ref):
  # on a follow-up reply whose first body token is NOT a numeric id, the handler
  # prepends the source card's `video_id` (read from the source event payload) as
  # a synthetic leading token. The rest of the body then parses as the `<when>`
  # through the normal ref-leading flow, so an id-less reply on a detail card
  # targets the card's video. Guards:
  #   - a typed numeric leading id is left untouched (prepend does NOT fire);
  #   - a blank source `video_id` (e.g. a video_list reply) is left untouched.
  #
  #   `#<handle> schedule <when>` (id-less, video_detail) → confirmation for the
  #       card's video_id.
  #   `#<handle> schedule <id> <when>` → confirmation for the TYPED id.
  describe "follow-up via video_detail source event" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "video_id" => SCHED_STUB_ID, "reply_target" => "video_detail" }
      )
    end

    # ── id-less when forms on a detail card → confirmation for the card's video ──
    #
    # prepend_follow_up_ref injects video_id (42) as the leading token, so the full
    # body parses as <ref=42> + <when>. publish_at is the parsed time for vid 42.
    {
      "tomorrow at 3pm"    => "2026-06-17T15:00:00Z",
      "tomorrow at noon"   => "2026-06-17T12:00:00Z",
      "in 2 days"          => "2026-06-18T09:00:00Z",
      "next monday"        => "2026-06-22T09:00:00Z",
      "for 20-07-2026 14:30" => "2026-07-20T14:30:00Z"
    }.each do |when_phrase, publish_at|
      it "id-less `schedule #{when_phrase}` on a video_detail card → :confirmation for vid #{SCHED_STUB_ID}" do
        ctx = Pito::Chat::FollowUpContext.new(source_event:, rest: when_phrase)
        result = call("schedule #{when_phrase}", follow_up: ctx)
        expect_confirmation(result, video_id: SCHED_STUB_ID, publish_at:)
      end
    end

    it "follow_up? is true (video_detail context carries source event)" do
      ctx = Pito::Chat::FollowUpContext.new(source_event:, rest: "tomorrow")
      handler = make_handler("schedule tomorrow", follow_up: ctx)
      expect(handler.follow_up?).to be true
    end

    # ── A typed id still wins — prepend only fires when no numeric leading ref ───
    #
    # The source card is vid 42, but the reply explicitly types #7. prepend is a
    # no-op (first token is numeric), so the confirmation targets the TYPED id (7),
    # not the card's video_id.
    it "typed id on a video_detail reply targets the TYPED id, not the card's video" do
      typed = double("Video", id: 7, title: "Typed Video")
      allow(typed).to receive(:assign_attributes)
      allow(typed).to receive(:valid?).with(:schedule).and_return(true)
      allow(typed).to receive(:restore_attributes)
      allow(typed).to receive(:already_published?).and_return(false)
      allow(::Video).to receive(:find_by).with(id: "7").and_return(typed)
      ctx = Pito::Chat::FollowUpContext.new(source_event:, rest: "7 tomorrow")
      result = call("schedule 7 tomorrow", follow_up: ctx)
      expect_confirmation(result, video_id: 7, publish_at: "2026-06-17T09:00:00Z")
    end

    # ── Bare `#<h> schedule` (no when) on a detail card → needs_ref ──────────────
    #
    # Verified: prepend_follow_up_ref guards on `body.empty?` and returns early, so
    # the synthetic id is NOT injected when nothing is typed. The empty-body
    # `needs_ref` check fires before any <when> parsing → needs_ref (not bad_when).
    it "bare `schedule` (no when) on a video_detail card → needs_ref" do
      ctx = Pito::Chat::FollowUpContext.new(source_event:, rest: "")
      result = call("schedule", follow_up: ctx)
      expect_needs_ref(result)
    end
  end

  # ── video_list reply with NO single video_id → still needs the typed id ───────
  #
  # A video_list source carries `video_ids` (a collection), not a single
  # `video_id`. prepend_follow_up_ref reads `video_id` (blank here) → no prepend,
  # so an id-less list reply cannot resolve a target.
  describe "video_list reply has no single video_id → no prepend" do
    let(:list_event) do
      instance_double(
        Event,
        payload: {
          "reply_target" => "video_list",
          "video_ids"    => [ SCHED_STUB_ID ] # collection, NOT a scalar video_id
        }
      )
    end

    it "id-less `schedule tomorrow at 3pm` on a list reply → :system not-found (ref='tomorrow')" do
      # No scalar video_id → no prepend. Body parses <ref='tomorrow'> + <at 3pm>;
      # 'tomorrow' is non-numeric → resolve_video nil → not-found :system event.
      ctx = Pito::Chat::FollowUpContext.new(source_event: list_event, rest: "tomorrow at 3pm")
      result = call("schedule tomorrow at 3pm", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end

    it "id-less `schedule tomorrow` (no parseable when after split) on a list reply → bad_when" do
      ctx = Pito::Chat::FollowUpContext.new(source_event: list_event, rest: "tomorrow")
      result = call("schedule tomorrow", follow_up: ctx)
      expect_bad_when(result)
    end
  end

  # ── Mass form (WP3): `schedule <id> <when>, <id> <when>, …` ──────────────────
  #
  # Grammar: a comma ANYWHERE in the (noun-filler-stripped) body routes to the
  # mass ladder; no comma stays the single path, byte-identical (see "grammar
  # detection" below). Real Lexer+KeywordSanitizer+Parser build body_tokens
  # here — NOT the naive whitespace-splitter `make_handler`/`call` use above —
  # because mass detection depends on a genuine :comma TOKEN, and the naive
  # splitter never produces one unless a comma is its own whitespace-separated
  # word, which is not how anyone types `schedule 5 tomorrow, 6 in 2 hours`.
  # DB stays mocked, same spirit as the rest of this file: ::Video.where is
  # stubbed per-example against hand-built doubles (mirrors video_double /
  # SCHED_STUB_ID above), never a real AR query — except the "not found" case,
  # which deliberately stubs an id OUT so the lookup misses it.
  describe "mass form (WP3)" do
    def mass_handler(raw, follow_up: nil)
      tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(raw))
      msg    = Pito::Chat::Parser.call(tokens, raw: raw, conversation: conversation)
      Pito::Chat::Handlers::Schedule.new(message: msg, conversation: conversation, follow_up: follow_up)
    end

    def mass_call(raw, follow_up: nil)
      mass_handler(raw, follow_up:).call
    end

    def mass_video(id:, title:, channel_id: 1, published: false)
      v = double("Video##{id}", id: id, title: title, channel_id: channel_id)
      # YouTube's own status.publishAt constraint (Video#already_published?) —
      # default eligible; the dedicated "eligibility" section below sets
      # published: true to exercise the guard.
      allow(v).to receive(:already_published?).and_return(published)
      v
    end

    def stub_mass_videos(*doubles)
      by_id = doubles.index_by { |v| v.id.to_s }
      allow(::Video).to receive(:where) do |cond|
        ids = Array(cond[:id]).map(&:to_s)
        by_id.values_at(*ids).compact
      end
    end

    def expect_mass_abort(result, includes:)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["command"]).to be_nil
      expect(event[:payload]["text"]).to include(includes)
    end

    describe "grammar detection" do
      it "a comma anywhere routes to the mass ladder, not the single path" do
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours")
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["command"]).to eq("video_schedule_mass")
      end

      it "no comma stays the single path — byte-identical, untouched by WP3" do
        result = mass_call("schedule 5 tomorrow")
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["command"]).to eq("video_schedule")
      end
    end

    describe "stage 1 — parse: TimeParser match AND a single numeric #?\\d+ ref" do
      it "an unparseable trailing segment aborts, naming that segment" do
        result = mass_call("schedule 5 tomorrow, 6 blah")
        expect_mass_abort(result, includes: "6 blah")
      end

      it "an unparseable LEADING segment aborts too — every segment is checked before any later stage" do
        result = mass_call("schedule 5 blah, 6 tomorrow")
        expect_mass_abort(result, includes: "5 blah")
      end

      it "a non-numeric (title) ref aborts — mass has no title resolution" do
        result = mass_call("schedule five tomorrow, 6 in 2 hours")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end

      it "a dangling trailing comma yields an empty segment and aborts" do
        result = mass_call("schedule 5 tomorrow,")
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    describe "stage 2 — no duplicate ids across segments" do
      it "the same id twice aborts naming the id, before any DB lookup" do
        result = mass_call("schedule 5 tomorrow, 5 in 2 hours")
        expect_mass_abort(result, includes: "5")
      end

      it "#5 and bare 5 (same id, different ref spelling) still count as a duplicate" do
        result = mass_call("schedule #5 tomorrow, 5 in 2 hours")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end
    end

    describe "stage 3 — every id must resolve to a real vid" do
      it "an id with no matching vid aborts naming that segment" do
        stub_mass_videos(mass_video(id: 5, title: "V5"))
        result = mass_call("schedule 5 tomorrow, 999999 in 2 hours")
        expect_mass_abort(result, includes: "999999")
      end
    end

    describe "eligibility — no vid may already be public on YouTube" do
      it "a batch item that's already public aborts the WHOLE batch, naming it — even though the other segment is fine" do
        stub_mass_videos(
          mass_video(id: 5, title: "V5", published: true),
          mass_video(id: 6, title: "V6")
        )
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours")
        expect_mass_abort(result, includes: "V5")
      end
    end

    describe "stage 4 — every <when> must be future AND at least 30 minutes out" do
      it "a past segment aborts naming it, even though the other segment is fine" do
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        result = mass_call("schedule 5 in 2 hours, 6 01-01-2020")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end

      it "a too-soon segment (under 30 minutes) aborts" do
        # SCHED_NOW = 2026-06-16 10:00 UTC (the file's own `around` hook).
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        result = mass_call("schedule 5 in 2 hours, 6 in 10m")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end
    end

    describe "stage 5 — spacing: the law's verdict aborts the batch" do
      it "a segment the law rejects aborts, naming the offender" do
        stub_mass_videos(
          mass_video(id: 5, title: "V5"),
          mass_video(id: 6, title: "V6")
        )
        allow(Pito::Schedule::SpacingPolicy).to receive(:call).and_return(
          { kind: :spacing, title: "Existing Anchor", at: Time.zone.local(2026, 7, 1, 9, 30) }
        )
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours")
        expect_mass_abort(result, includes: "Existing Anchor")
      end

      it "a day-cap verdict aborts naming the 24h window pair" do
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        allow(Pito::Schedule::SpacingPolicy).to receive(:call).and_return(
          { kind: :day_cap, titles: [ "A", "B" ], at: Time.zone.local(2026, 7, 1, 9, 30) }
        )
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include("third publish")
      end
    end

    describe "stage 5 — spacing: batch siblings feed the law (extra:)" do
      it "the second same-channel row is judged WITH the first as an extra sibling" do
        stub_mass_videos(
          mass_video(id: 5, title: "V5", channel_id: 1),
          mass_video(id: 6, title: "V6", channel_id: 1)
        )
        mass_call("schedule 5 today at 14:00, 6 today at 18:00")
        expect(Pito::Schedule::SpacingPolicy).to have_received(:call).with(
          hash_including(extra: [ hash_including(title: "V5") ])
        ).once
      end

      it "a DIFFERENT-channel first row is NOT among the second row's siblings" do
        stub_mass_videos(
          mass_video(id: 5, title: "V5", channel_id: 1),
          mass_video(id: 6, title: "V6", channel_id: 2)
        )
        mass_call("schedule 5 today at 14:00, 6 today at 14:20")
        expect(Pito::Schedule::SpacingPolicy).not_to have_received(:call).with(
          hash_including(extra: [ hash_including(title: "V5") ])
        )
      end
    end

    describe "happy path — confirmation payload" do
      it "builds a video_schedule_mass confirmation with items sorted ascending by publish_at" do
        stub_mass_videos(
          mass_video(id: 5, title: "Later One", channel_id: 1),
          mass_video(id: 6, title: "Earlier One", channel_id: 2)
        )
        result  = mass_call("schedule 5 tomorrow, 6 in 2 hours")
        event   = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        payload = event[:payload]
        expect(payload["command"]).to eq("video_schedule_mass")
        ids = payload["items"].map { |i| i["video_id"] }
        expect(ids).to eq([ 6, 5 ]) # "in 2 hours" (#6) lands before "tomorrow" (#5)
      end

      it "3+ segments that all clear the ladder → one confirmation" do
        stub_mass_videos(
          mass_video(id: 5, title: "V5", channel_id: 1),
          mass_video(id: 6, title: "V6", channel_id: 2),
          mass_video(id: 7, title: "V7", channel_id: 3)
        )
        result = mass_call("schedule 5 in 2 hours, 6 tomorrow, 7 next week")
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["items"].size).to eq(3)
      end
    end

    # ── video_list / video_search mass reply follow-ups ────────────────────────
    #
    # Mirrors the single path's own follow-up sections above: the ToolDelegator
    # re-enters Pito::Dispatch::Router with the FULL rest (tool word included),
    # so the handler sees the same body_tokens (comma included) it would from
    # free chat — one code path, no reply-specific mass branching.
    # prepend_follow_up_ref no-ops on a mass reply since the first typed token
    # is always numeric (the first segment's id).
    describe "video_list / video_search mass reply follow-ups" do
      let(:list_event) do
        instance_double(Event, payload: { "reply_target" => "video_list", "video_ids" => [ 5, 6 ] })
      end
      let(:search_event) do
        instance_double(Event, payload: { "reply_target" => "video_search", "video_ids" => [ 5, 6 ] })
      end

      it "a mass reply on a video_list card runs the SAME mass path as free chat" do
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        ctx    = Pito::Chat::FollowUpContext.new(source_event: list_event, rest: "5 tomorrow, 6 in 2 hours")
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours", follow_up: ctx)
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["command"]).to eq("video_schedule_mass")
      end

      it "follow_up? is true for a mass reply" do
        ctx     = Pito::Chat::FollowUpContext.new(source_event: list_event, rest: "5 tomorrow, 6 in 2 hours")
        handler = mass_handler("schedule 5 tomorrow, 6 in 2 hours", follow_up: ctx)
        expect(handler.follow_up?).to be true
      end

      it "a ladder failure on a mass reply aborts the same way as free chat" do
        ctx    = Pito::Chat::FollowUpContext.new(source_event: list_event, rest: "5 tomorrow, 5 in 2 hours")
        result = mass_call("schedule 5 tomorrow, 5 in 2 hours", follow_up: ctx)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end

      it "a mass reply on a video_search card runs the same mass path too" do
        stub_mass_videos(mass_video(id: 5, title: "V5"), mass_video(id: 6, title: "V6"))
        ctx    = Pito::Chat::FollowUpContext.new(source_event: search_event, rest: "5 tomorrow, 6 in 2 hours")
        result = mass_call("schedule 5 tomorrow, 6 in 2 hours", follow_up: ctx)
        expect(result.events.first[:kind]).to eq(:confirmation)
      end
    end
  end
end
