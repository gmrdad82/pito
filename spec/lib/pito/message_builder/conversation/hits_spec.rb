# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Conversation::Hits do
  let(:conversation) { Conversation.singleton }

  # like (semantic) hits: "score" non-nil, "occurrence_count" nil — the mode
  # SearchConversations#rank_by_distance stamps (see build_hits).
  let(:like_hit1) do
    {
      "title"             => "Talking about Elden Ring",
      "score"             => 87,
      "occurrence_count"  => nil,
      "anchor_event_id"   => 101,
      "conversation_uuid" => "conv-uuid-1"
    }
  end

  let(:like_hit2) do
    {
      "title"             => "Scheduling the next upload",
      "score"             => 42,
      "occurrence_count"  => nil,
      "anchor_event_id"   => 202,
      "conversation_uuid" => "conv-uuid-2"
    }
  end

  # for/bare (lexical) hits: "occurrence_count" non-nil, "score" nil — the
  # mode SearchConversations#rank_by_recency stamps.
  let(:for_hit1) do
    {
      "title"             => "Talking about Elden Ring",
      "score"             => nil,
      "occurrence_count"  => 3,
      "anchor_event_id"   => 101,
      "conversation_uuid" => "conv-uuid-1"
    }
  end

  let(:for_hit2) do
    {
      "title"             => "Scheduling the next upload",
      "score"             => nil,
      "occurrence_count"  => 1,
      "anchor_event_id"   => 202,
      "conversation_uuid" => "conv-uuid-2"
    }
  end

  describe ".call" do
    subject(:payload) { described_class.call(hits, conversation: conversation) }

    context "like mode (first hit carries a non-nil score)" do
      let(:hits) { [ like_hit1, like_hit2 ] }

      it "returns a payload with body, html, table_heading, and table_rows" do
        expect(payload.keys).to include("body", "html", "table_heading", "table_rows")
      end

      it "sets html to true" do
        expect(payload["html"]).to be true
      end

      it "sets table_heading to the builder's frozen LIKE_TABLE_HEADING" do
        expect(payload["table_heading"]).to eq(described_class::LIKE_TABLE_HEADING)
        expect(payload["table_heading"]).to eq([ "Conversation", "Similarity" ])
      end

      it "renders without raising" do
        expect { payload }.not_to raise_error
      end

      it "body is present" do
        expect(payload["body"]).to be_present
      end

      it "body reflects the hit count" do
        expect(payload["body"]).to include("2")
      end

      it "body uses the plural noun 'conversations'" do
        expect(payload["body"]).to include("conversations")
      end

      it "returns one row per hit, in input order" do
        rows = payload["table_rows"]
        expect(rows.size).to eq(2)
        expect(rows[0][:cells][0][:text]).to eq(like_hit1["title"])
        expect(rows[1][:cells][0][:text]).to eq(like_hit2["title"])
      end

      it "does not stamp follow-up keys (this card is not follow-up-able)" do
        expect(payload).not_to have_key("reply_handle")
        expect(payload).not_to have_key("reply_target")
        expect(payload).not_to have_key(:reply_handle)
        expect(payload).not_to have_key(:reply_target)
      end
    end

    context "for mode (first hit carries a non-nil occurrence_count, nil score)" do
      let(:hits) { [ for_hit1, for_hit2 ] }

      it "sets table_heading to the builder's frozen FOR_TABLE_HEADING" do
        expect(payload["table_heading"]).to eq(described_class::FOR_TABLE_HEADING)
        expect(payload["table_heading"]).to eq([ "Conversation", "Occurrences" ])
      end

      it "returns one row per hit, in input order" do
        rows = payload["table_rows"]
        expect(rows.size).to eq(2)
        expect(rows[0][:cells][0][:text]).to eq(for_hit1["title"])
        expect(rows[1][:cells][0][:text]).to eq(for_hit2["title"])
      end
    end

    context "with exactly one hit" do
      let(:hits) { [ like_hit1 ] }

      it "body reflects the count of 1" do
        expect(payload["body"]).to include("1")
      end

      it "body uses the singular noun 'conversation' (not 'conversations')" do
        expect(payload["body"]).to include("conversation")
        expect(payload["body"]).not_to include("conversations")
      end

      it "returns exactly one row" do
        expect(payload["table_rows"].size).to eq(1)
      end
    end

    describe "like-mode row shape" do
      let(:hits) { [ like_hit1 ] }
      let(:row) { payload["table_rows"].first }
      let(:resume_command) { "/resume #{like_hit1['conversation_uuid']}" }

      it "builds cells as [clickable name, score] with symbol keys" do
        expect(row[:cells]).to eq([
          {
            text:  like_hit1["title"],
            class: Pito::Shimmer::TokenComponent.css_class(like_hit1["title"], extra: "pito-cell-title", clickable: true),
            data:  Pito::Shimmer::TokenComponent.prefill_data(resume_command, submit: true)
          },
          { score: like_hit1["score"].to_i }
        ])
      end

      it "the name cell prefills+submits '/resume <conversation_uuid>' (no anchor id)" do
        expect(row[:cells][0][:data]).to eq(Pito::Shimmer::TokenComponent.prefill_data(resume_command, submit: true))
      end

      it "pins the row-level data contract exactly (anchor-jump DOM contract)" do
        expect(row[:data]).to eq({
          "anchor_event_id"   => like_hit1["anchor_event_id"],
          "conversation_uuid" => like_hit1["conversation_uuid"]
        })
      end

      it "data is keyed with a symbol at the row level" do
        expect(row).to have_key(:data)
        expect(row).not_to have_key("data")
      end

      it "data's inner keys are strings" do
        expect(row[:data].keys).to all(be_a(String))
      end
    end

    describe "for-mode row shape" do
      let(:hits) { [ for_hit1 ] }
      let(:row) { payload["table_rows"].first }
      let(:resume_command) { "/resume #{for_hit1['conversation_uuid']} #{for_hit1['anchor_event_id']}" }

      it "builds cells as [clickable name, occurrence text] with symbol keys" do
        expect(row[:cells]).to eq([
          {
            text:  for_hit1["title"],
            class: Pito::Shimmer::TokenComponent.css_class(for_hit1["title"], extra: "pito-cell-title", clickable: true),
            data:  Pito::Shimmer::TokenComponent.prefill_data(resume_command, submit: true)
          },
          { text: for_hit1["occurrence_count"].to_s, class: "tabular-nums text-right whitespace-nowrap" }
        ])
      end

      it "the name cell prefills+submits '/resume <conversation_uuid> <anchor_event_id>'" do
        expect(row[:cells][0][:data]).to eq(Pito::Shimmer::TokenComponent.prefill_data(resume_command, submit: true))
      end

      it "pins the row-level data contract exactly (anchor-jump DOM contract)" do
        expect(row[:data]).to eq({
          "anchor_event_id"   => for_hit1["anchor_event_id"],
          "conversation_uuid" => for_hit1["conversation_uuid"]
        })
      end
    end

    describe "no snippet column and no trailing anchor '#' column, in either mode" do
      it "a like-mode row has exactly two cells" do
        row = described_class.call([ like_hit1 ], conversation: conversation)["table_rows"].first
        expect(row[:cells].size).to eq(2)
      end

      it "a for-mode row has exactly two cells" do
        row = described_class.call([ for_hit1 ], conversation: conversation)["table_rows"].first
        expect(row[:cells].size).to eq(2)
      end

      it "no cell renders the bare anchor '#<id>' text" do
        row = described_class.call([ for_hit1 ], conversation: conversation)["table_rows"].first
        expect(row[:cells].map { |c| c[:text] }).not_to include("##{for_hit1['anchor_event_id']}")
      end
    end
  end
end
