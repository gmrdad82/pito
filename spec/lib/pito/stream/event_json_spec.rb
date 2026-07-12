# frozen_string_literal: true

require "rails_helper"

# The JSON projection's additions happen at PROJECTION time, never persist
# time: `text` for message_key payloads (covered via broadcaster/show-json
# specs) and — here — the thinking word pools (`words` + resolved `word`)
# that keep an older TUI binary from showing stale spinner verbs after a
# copy deploy.
RSpec.describe Pito::Stream::EventJson do
  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :slash, input_text: "/help") }

  def thinking_event(payload)
    turn.events.create!(
      conversation:, kind: :thinking, position: turn.events.count + 1, payload:
    )
  end

  describe "thinking word enrichment" do
    it "adds words (the CURRENT doing pool) to an unresolved indicator" do
      event = thinking_event(
        "dictionary" => "chat", "order" => [ 2, 0, 1 ], "started_at" => Time.current.iso8601
      )

      payload = described_class.call(event)[:payload]

      expect(payload["words"]).to eq(Array(I18n.t("pito.copy.thinking.chat.doing")))
      expect(payload).not_to have_key("word")
      expect(event.reload.payload).not_to have_key("words")
    end

    it "adds the past-tense word at word_index once resolved" do
      event = thinking_event(
        "dictionary" => "chat", "order" => [ 2, 0, 1 ],
        "resolved" => true, "elapsed_seconds" => 1.2, "word_index" => 2
      )

      payload = described_class.call(event)[:payload]

      expect(payload["word"]).to eq(Array(I18n.t("pito.copy.thinking.chat.done"))[2])
      expect(payload["words"]).to be_present
    end

    it "leaves a retired dictionary's payload untouched" do
      event = thinking_event("dictionary" => "no_such_dictionary", "order" => [ 0 ])

      payload = described_class.call(event)[:payload]

      expect(payload).not_to have_key("words")
      expect(payload).not_to have_key("word")
    end

    it "does not enrich non-thinking events" do
      event = turn.events.create!(
        conversation:, kind: :system, position: 1,
        payload: { "dictionary" => "chat", "text" => "hi" }
      )

      expect(described_class.call(event)[:payload]).not_to have_key("words")
    end
  end
end
