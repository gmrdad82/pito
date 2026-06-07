# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ThinkingComponent do
  let(:conversation) { create(:conversation) }
  let(:turn) { create(:turn, conversation:) }
  let(:event) do
    create(:event, turn:, kind: :thinking, payload: { "dictionary" => "slash", "word_index" => 2 })
  end

  it "renders a spinning Braille indicator when the turn is incomplete" do
    node = render_inline(described_class.new(payload: event.payload, event:))

    expect(node.css(".pito-thinking[data-controller='pito--thinking']")).not_to be_empty
    expect(node.css(".pito-thinking__braille").text).to eq("⠋")
    expect(node.css(".pito-thinking__word").text).to eq(
      "#{I18n.t('pito.copy.thinking.slash.doing')[2]}…"
    )
  end

  it "renders a resolved message when the turn is complete" do
    turn.update!(completed_at: 3.seconds.after(turn.started_at))
    event.update!(payload: event.payload.merge("resolved" => true, "elapsed_seconds" => 3.0))

    node = render_inline(described_class.new(payload: event.payload, event:))

    done_word = I18n.t("pito.copy.thinking.slash.done")[2]
    expect(node.css(".pito-thinking__message").text).to eq(
      I18n.t("pito.event.thinking.resolved", word: done_word, elapsed: 3.0)
    )
    expect(node.css(".pito-thinking__braille")).to be_empty
  end

  it "picks the chat dictionary" do
    chat_event = create(:event, turn:, kind: :thinking, payload: { "dictionary" => "chat", "word_index" => 1 })
    node = render_inline(described_class.new(payload: chat_event.payload, event: chat_event))

    expect(node.css(".pito-thinking__word").text).to eq("Pondering…")
  end

  it "uses the word_index from payload (idempotent)" do
    expected_word = "#{I18n.t('pito.copy.thinking.slash.doing')[2]}…"

    node1 = render_inline(described_class.new(payload: event.payload, event:))
    expect(node1.css(".pito-thinking__word").text).to eq(expected_word)

    # Re-render with the same payload — same word
    node2 = render_inline(described_class.new(payload: event.payload, event:))
    expect(node2.css(".pito-thinking__word").text).to eq(expected_word)
  end

  it "assigns a DOM id when the event is present" do
    node = render_inline(described_class.new(payload: event.payload, event:))
    expect(node.css(".pito-segment[id='event_#{event.id}']")).not_to be_empty
  end

  it "exposes Braille frames as JSON" do
    component = described_class.new(payload: event.payload, event:)
    expect(component.braille_frames_json).to eq(%w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].to_json)
  end

  it "exposes doing words as JSON for the dictionary" do
    component = described_class.new(payload: event.payload, event:)
    words = JSON.parse(component.doing_words_json)
    expect(words).to include("Executing")
    expect(words).to include("Frobnicating")
  end

  it "exposes done words as JSON for the dictionary" do
    component = described_class.new(payload: event.payload, event:)
    words = JSON.parse(component.done_words_json)
    expect(words).to include("Executed")
    expect(words).to include("Frobnicated")
  end

  describe "fallbacks" do
    it "falls back to the first doing word if the index is out of range" do
      payload = { "dictionary" => "slash", "word_index" => 999 }
      node = render_inline(described_class.new(payload:, event: nil))

      expect(node.css(".pito-thinking__word").text).to eq("Executing…")
    end
  end
end
