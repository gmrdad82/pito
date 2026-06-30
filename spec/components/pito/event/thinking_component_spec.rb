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
    # elapsed 3.0 → formatted "3" (trailing decimal zeros stripped)
    expect(node.css(".pito-thinking__message").text).to eq(
      I18n.t("pito.event.thinking.resolved", word: done_word, elapsed: "3")
    )
    expect(node.css(".pito-thinking__braille")).to be_empty
  end

  it "shows a resolved glyph from GLYPHS in place of the braille spinner" do
    event.update!(payload: event.payload.merge("resolved" => true, "elapsed_seconds" => 1.0))

    node = render_inline(described_class.new(payload: event.payload, event:))

    glyph_text = node.css(".pito-thinking__glyph").text
    expect(described_class::GLYPHS).to include(glyph_text)
  end

  it "picks the same glyph on every re-render of the same resolved event" do
    event.update!(payload: event.payload.merge("resolved" => true, "elapsed_seconds" => 1.0))

    glyph1 = render_inline(described_class.new(payload: event.payload, event:)).css(".pito-thinking__glyph").text
    glyph2 = render_inline(described_class.new(payload: event.payload, event:)).css(".pito-thinking__glyph").text

    expect(glyph1).to eq(glyph2)
    expect(glyph1).not_to be_empty
  end

  it "shows no glyph while the thinking block is still spinning" do
    node = render_inline(described_class.new(payload: event.payload, event:))

    expect(node.css(".pito-thinking__glyph")).to be_empty
  end

  describe "elapsed formatting in resolved label" do
    def resolved_text(elapsed_seconds)
      event.update!(payload: event.payload.merge("resolved" => true, "elapsed_seconds" => elapsed_seconds, "word_index" => 2))
      node = render_inline(described_class.new(payload: event.payload, event:))
      node.css(".pito-thinking__message").text
    end

    it "shows sub-second elapsed to 2 decimal places (0.224 → '0.22s')" do
      expect(resolved_text(0.224)).to include("0.22s")
    end

    it "trims trailing zero from sub-second elapsed (0.5 → '0.5s')" do
      expect(resolved_text(0.5)).to include("0.5s")
    end

    it "shows whole-second elapsed without decimals (1.0 → '1s')" do
      expect(resolved_text(1.0)).to include("1s")
      expect(resolved_text(1.0)).not_to include("1.0s")
    end

    it "shows two decimal places when both are significant (2.47 → '2.47s')" do
      expect(resolved_text(2.47)).to include("2.47s")
    end

    it "trims one trailing zero from one-decimal elapsed (12.3 → '12.3s')" do
      expect(resolved_text(12.3)).to include("12.3s")
    end
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

  # ── Per-message indicators (H5.4) ───────────────────────────────────────────

  describe "per-message indicator" do
    it "derives its own elapsed/verb from its own started_at, ignoring for_event_id" do
      doing   = I18n.t("pito.copy.thinking.slash.doing")
      order   = [ 1, 2, 0 ]
      elapsed = described_class::INTERVAL_SECONDS + 1 # step 1 → order[1] = 2
      payload = {
        "dictionary" => "slash", "order" => order,
        "started_at" => elapsed.seconds.ago.iso8601, "for_event_id" => 12_345
      }

      node = render_inline(described_class.new(payload:, event: nil))
      expect(node.css(".pito-thinking__word").text).to eq("#{doing[2]}…")
    end

    it "re-renders a resolved per-message indicator as the past-tense form on refresh" do
      payload = {
        "dictionary" => "slash", "order" => [ 2, 0, 1 ], "resolved" => true,
        "elapsed_seconds" => 4.0, "word_index" => 2, "for_event_id" => 678
      }
      node = render_inline(described_class.new(payload:, event: nil))

      done_word = I18n.t("pito.copy.thinking.slash.done")[2]
      # elapsed 4.0 → formatted "4" (trailing decimal zeros stripped)
      expect(node.css(".pito-thinking__message").text).to eq(
        I18n.t("pito.event.thinking.resolved", word: done_word, elapsed: "4")
      )
    end
  end

  describe "fallbacks" do
    it "falls back to the first doing word if the index is out of range" do
      payload = { "dictionary" => "slash", "word_index" => 999 }
      node = render_inline(described_class.new(payload:, event: nil))

      expect(node.css(".pito-thinking__word").text).to eq("Executing…")
    end
  end

  # ── Verb cycling (order + elapsed) ──────────────────────────────────────────

  describe ".word_index_at" do
    let(:order) { [ 3, 1, 2, 0 ] }

    it "returns the first index before one interval elapses" do
      expect(described_class.word_index_at(order:, elapsed_seconds: 0)).to eq(3)
      expect(described_class.word_index_at(order:, elapsed_seconds: described_class::INTERVAL_SECONDS - 1)).to eq(3)
    end

    it "advances one step per INTERVAL_SECONDS and wraps around" do
      i = described_class::INTERVAL_SECONDS
      expect(described_class.word_index_at(order:, elapsed_seconds: i)).to eq(1)
      expect(described_class.word_index_at(order:, elapsed_seconds: 2 * i)).to eq(2)
      expect(described_class.word_index_at(order:, elapsed_seconds: 4 * i)).to eq(3) # wrapped
    end

    it "returns 0 for a blank order" do
      expect(described_class.word_index_at(order: [], elapsed_seconds: 99)).to eq(0)
    end
  end

  describe "current word reflects elapsed time" do
    it "shows the verb for the step the turn is currently on" do
      doing   = I18n.t("pito.copy.thinking.slash.doing")
      order   = [ 3, 1, 2, 0 ]
      elapsed = 2 * described_class::INTERVAL_SECONDS + 1 # step 2 → order[2] = 2
      payload = { "dictionary" => "slash", "order" => order, "started_at" => elapsed.seconds.ago.iso8601 }

      node = render_inline(described_class.new(payload:, event: nil))
      expect(node.css(".pito-thinking__word").text).to eq("#{doing[2]}…")
    end
  end

  describe "cycling data values" do
    let(:payload) do
      { "dictionary" => "slash", "order" => [ 2, 0, 1 ], "started_at" => Time.current.iso8601 }
    end

    it "exposes the order as JSON" do
      expect(JSON.parse(described_class.new(payload:, event: nil).order_json)).to eq([ 2, 0, 1 ])
    end

    it "exposes the interval in milliseconds (single source of truth)" do
      component = described_class.new(payload:, event: nil)
      expect(component.interval_ms).to eq(described_class::INTERVAL_SECONDS * 1000)
    end

    it "renders the cycling data attributes for the Stimulus controller" do
      node = render_inline(described_class.new(payload:, event: nil))
      root = node.css(".pito-thinking").first

      expect(root["data-pito--thinking-interval-value"]).to eq((described_class::INTERVAL_SECONDS * 1000).to_s)
      expect(root["data-pito--thinking-order-value"]).to eq([ 2, 0, 1 ].to_json)
      expect(root["data-pito--thinking-words-value"]).to be_present
      expect(root["data-pito--thinking-started-at-value"]).to be_present
      expect(node.css(".pito-thinking__word[data-pito--thinking-target='word']")).not_to be_empty
    end
  end
end
