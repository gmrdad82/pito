# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Schedule do
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

  it "emits a :confirmation event when given YYYY-MM-DD HH:MM" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "emits a :confirmation event when given YYYY-MM-DD only" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "does NOT update the video directly" do
    schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(video.reload.privacy_status).to eq("public")
    expect(video.reload.publish_at).to be_nil
  end

  it "carries command video_schedule in the confirmation payload" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result.events.first[:payload]["command"]).to eq("video_schedule")
  end

  it "carries publish_at as an ISO8601 string in the confirmation payload" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d')}")
    payload = result.events.first[:payload]
    expect(payload["publish_at"]).to be_present
    expect { Time.iso8601(payload["publish_at"]) }.not_to raise_error
  end

  it "includes the video title in the confirmation body" do
    result = schedule_real("schedule video Episode One #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result.events.first[:payload]["body"]).to include("Episode One")
  end

  it "resolves by bare id" do
    result = schedule_real("schedule video #{video.id} #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves by #id" do
    result = schedule_real("schedule video ##{video.id} #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves with plural noun filler 'videos'" do
    result = schedule_real("schedule videos #{video.id} #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
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
    result = schedule_real("schedule video #{video.id} 2025-99-01")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.bad_when")
  end

  it "returns a witty in-past error for a past date" do
    result = schedule_real("schedule video Episode One 2020-01-01")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("Episode One")
  end

  it "returns too_soon error for a time less than 30 minutes from now" do
    soon = 10.minutes.from_now.utc
    result = schedule_real("schedule video Episode One #{soon.strftime('%Y-%m-%d %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.schedule.too_soon")
  end

  it "emits a confirmation for a time exactly 30 minutes from now (boundary)" do
    # 31 minutes to be safely above the 30m threshold regardless of execution timing
    future = 31.minutes.from_now.utc
    result = schedule_real("schedule video Episode One #{future.strftime('%Y-%m-%d %H:%M')}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "returns a witty not-found for an unknown video reference" do
    result = schedule_real("schedule video nonexistent #{7.days.from_now.strftime('%Y-%m-%d')}")
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  context "video title with apostrophe resolved via real lexer/parser" do
    let!(:apos_video) { create(:video, channel: channel, title: "Let's Play Bloodborne") }

    it "resolves the video and emits a confirmation with a date" do
      result = schedule_real("schedule video Let's Play Bloodborne #{7.days.from_now.strftime('%Y-%m-%d')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "resolves with a datetime HH:MM and emits a confirmation" do
      result = schedule_real("schedule video Let's Play Bloodborne #{7.days.from_now.strftime('%Y-%m-%d %H:%M')}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end
  end
end
