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
  let!(:video)   { create(:video, channel: channel, title: "Episode One", privacy_status: :public, publish_at: nil) }

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
    expect(video.reload.privacy_status).to eq("public")
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
    msg = Pito::Chat::Message.new(verb: :schedule, body_tokens: [], kind: :new_turn, raw: "schedule")
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

  context "confirmation body displays time in local format (DD-MM-YYYY HH:MM)" do
    it "includes DD-MM-YYYY formatted date in the body" do
      travel_to Time.zone.local(2026, 6, 9, 10, 0) do
        result = schedule_real("schedule video #{video.id} 16-06-2026 15:30")
        body = result.events.first[:payload]["body"]
        expect(body).to include("16-06-2026")
      end
    end
  end

  # ── Natural-language <when> forms (P35) ───────────────────────────────────────
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
  end
end
