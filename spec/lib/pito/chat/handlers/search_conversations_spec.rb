# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::SearchConversations do
  let(:conversation) { Conversation.singleton }

  def build_message(raw)
    Pito::Chat::Parser.call(Pito::Lex::Lexer.call(raw), raw:, conversation:)
  end

  def search(raw)
    msg = build_message(raw)
    described_class.new(message: msg, conversation:).call
  end

  def payload_of(result)
    result.events.first[:payload]
  end

  # Reconstruct the per-conversation hits from the dedicated card builder's
  # payload (Pito::MessageBuilder::Conversation::Hits): title/snippet from the
  # cells, anchor_event_id/conversation_uuid from the row-level data. There is
  # NO conversation_id in the card payload — the card identifies a hit by uuid
  # (a hit is only fetchable by uuid cross-conversation), so logic assertions
  # key on uuid.
  def hits_of(result)
    Array(table_rows_of(result)).map do |row|
      {
        "title"             => row[:cells][0][:text],
        "snippet"           => row[:cells][1][:text],
        "anchor_event_id"   => row[:data]["anchor_event_id"],
        "conversation_uuid" => row[:data]["conversation_uuid"]
      }
    end
  end

  def table_rows_of(result)
    payload_of(result)["table_rows"]
  end

  # One seeded scrollback event, wired to a fresh turn on the SAME conversation
  # so it looks like a real turn. `text` lands in payload["text"] — both the
  # `for`/bare ILIKE substring scan and EventText's snippet projection read it.
  # `embedding`/`created_at`, when given, are written directly via
  # update_column (mirroring Pito::Embedding::EventIndexer's own writes).
  def seed_event(convo, position:, text: "unrelated filler", kind: "echo", embedding: nil, created_at: nil)
    turn  = create(:turn, conversation: convo)
    event = create(:event, conversation: convo, turn:, kind:, position:, payload: { "text" => text })
    event.update_column(:embedding, embedding) if embedding
    event.update_column(:created_at, created_at) if created_at
    event
  end

  # A 768-dim vector with `dims` set to 1.0 and everything else 0.0 — enough
  # to steer the cosine angle (and thus distance) between the stubbed query
  # embedding and a seeded event's embedding without caring about magnitude
  # (pgvector's `<=>` cosine operator normalizes internally).
  def vec(*dims)
    Array.new(768, 0.0).tap { |a| dims.each { |d| a[d] = 1.0 } }
  end

  def cosine_distance(a, b)
    dot    = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |x| x**2 })
    norm_b = Math.sqrt(b.sum { |x| x**2 })
    1 - (dot / (norm_a * norm_b))
  end

  def stub_embed(vector)
    client = instance_double(Pito::Embedding::Client)
    allow(Pito::Embedding::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed).and_return([ vector ])
    client
  end

  context "`for` / bare (lexical)" do
    it "groups hits per conversation, anchoring on the first matching event, and drops non-matching conversations" do
      matched = create(:conversation)
      seed_event(matched, position: 1, text: "nothing interesting")
      first_hit = seed_event(matched, position: 2, text: "we discussed zzflarp strategy")
      seed_event(matched, position: 3, text: "more zzflarp talk")

      other = create(:conversation)
      seed_event(other, position: 1, text: "also about zzflarp")

      unmatched = create(:conversation)
      seed_event(unmatched, position: 1, text: "totally unrelated")

      result = search("search conversations for zzflarp")
      hits   = hits_of(result).index_by { |h| h["conversation_uuid"] }

      expect(hits.keys).to contain_exactly(matched.uuid, other.uuid)
      expect(hits[matched.uuid]["anchor_event_id"]).to eq(first_hit.id)
      expect(hits[matched.uuid]["title"]).to eq(matched.display_name)

      # Each table_rows entry carries a row-level "data" key stamping its
      # anchor_event_id (Pito::Event::SystemComponent#normalized_table_rows
      # renders it as `data-anchor-event-id` on every cell span of the row) —
      # the DOM attribute contract a reply/anchor-jump behavior reads. Find the
      # matched conversation's row by its row-level conversation_uuid (the
      # name cell's clickable "#<id>" cell was dropped in 3.0.0 — see
      # Pito::MessageBuilder::Conversation::Hits).
      row = table_rows_of(result).find { |r| r[:data]["conversation_uuid"] == matched.uuid }
      expect(row[:data]).to eq("anchor_event_id" => first_hit.id, "conversation_uuid" => matched.uuid)
    end

    it "ranks conversations by occurrence count descending, breaking ties on anchor recency" do
      base_time = Time.current

      most = create(:conversation)
      5.times { |n| seed_event(most, position: n + 1, text: "zzflarp mention #{n}") }

      mid = create(:conversation)
      3.times { |n| seed_event(mid, position: n + 1, text: "zzflarp mention #{n}") }

      # Two single-occurrence conversations tie on occurrence_count (1) — the
      # more-recent anchor (#rank_by_occurrences' tiebreak key) must sort first.
      newer_single = create(:conversation)
      seed_event(newer_single, position: 1, text: "zzflarp once", created_at: base_time + 10.minutes)

      older_single = create(:conversation)
      seed_event(older_single, position: 1, text: "zzflarp once", created_at: base_time)

      result = search("search conversations for zzflarp")

      expect(hits_of(result).map { |h| h["conversation_uuid"] }).to eq(
        [ most.uuid, mid.uuid, newer_single.uuid, older_single.uuid ]
      )

      # "Occurrences" is the FOR_TABLE_HEADING's second column
      # (Pito::MessageBuilder::Conversation::Hits#for_cells) — read straight
      # off the rendered row cells rather than adding a new hits_of key.
      occurrence_counts = table_rows_of(result).map { |row| row[:cells][1][:text].to_i }
      expect(occurrence_counts).to eq([ 5, 3, 1, 1 ])
    end

    it "treats a bare query exactly like an explicit `for` query" do
      convo = create(:conversation)
      seed_event(convo, position: 1, text: "about zzflarp")
      decoy = create(:conversation)
      seed_event(decoy, position: 1, text: "nothing to do with it")

      for_hits  = hits_of(search("search conversations for zzflarp"))
      bare_hits = hits_of(search("search conversations zzflarp"))

      expect(bare_hits).to eq(for_hits)
    end
  end

  context "`like` (semantic)" do
    it "orders conversations by best cosine distance and still anchors each on its first matching event" do
      client = stub_embed(vec(0))

      # position 1 sits farther from the query than position 2 (the group's
      # best), but the anchor rule is position-ASC, not distance-ASC — this
      # proves the two are independent.
      close        = create(:conversation)
      close_anchor = seed_event(close, position: 1, embedding: vec(0, 1)) # distance ~0.293
      seed_event(close, position: 2, embedding: vec(0))                  # distance 0 (best, not anchor)

      mid = create(:conversation)
      seed_event(mid, position: 1, embedding: vec(0, 1, 2)) # distance ~0.423

      far = create(:conversation)
      seed_event(far, position: 1, embedding: vec(1)) # orthogonal, distance 1

      hits = hits_of(search("search conversations like anything"))

      expect(client).to have_received(:embed).with([ "anything" ])
      expect(hits.map { |h| h["conversation_uuid"] }).to eq([ close.uuid, mid.uuid, far.uuid ])
      expect(hits.first["anchor_event_id"]).to eq(close_anchor.id)
    end

    it "falls back to lexical ILIKE matching when the embedder returns a nil vector" do
      stub_embed(nil)

      convo     = create(:conversation)
      hit_event = seed_event(convo, position: 1, text: "we tuned the zzflarp combo timing")

      hits = hits_of(search("search conversations like zzflarp"))

      expect(hits.map { |h| h["conversation_uuid"] }).to eq([ convo.uuid ])
      expect(hits.first["anchor_event_id"]).to eq(hit_event.id)
    end

    it "stamps a similarity score rescaled via Pito::Recommendation::DisplayScore's CONVERSATION_FLOOR, not raw cosine × 100" do
      stub_embed(vec(0))

      convo = create(:conversation)
      seed_event(convo, position: 1, embedding: vec(0, 1)) # cosine distance ~0.293

      result = search("search conversations like anything")
      score  = table_rows_of(result).first[:cells].last[:score]

      distance = cosine_distance(vec(0), vec(0, 1))
      expected = Pito::Recommendation::DisplayScore.display_score(
        1.0 - distance, floor: Pito::Recommendation::DisplayScore::CONVERSATION_FLOOR
      ).round

      # Sanity: this distance is well above CONVERSATION_FLOOR's midpoint but
      # would have clamped near VID_FLOOR — proving the two floors are
      # independently tuned per embedding space, not shared.
      expect(expected).to be_between(1, 99)
      expect(score).to eq(expected)
    end
  end

  context "kind allowlist" do
    it "never matches error or thinking kinds even when their payload text contains the term" do
      convo = create(:conversation)
      seed_event(convo, position: 1, kind: "error", text: "zzflarp blew up")
      seed_event(convo, position: 2, kind: "thinking", text: "pondering zzflarp options")

      result = search("search conversations for zzflarp")

      expect(payload_of(result)["text"]).to eq(Pito::Copy.render("pito.copy.games.list_filter_empty"))
    end
  end

  context "empty results" do
    it "renders needs_seed copy for a blank query" do
      result = search("search conversations")

      expect(payload_of(result)["text"]).to eq(Pito::Copy.render("pito.chat.search.needs_seed"))
    end

    it "renders list_filter_empty copy when a real query matches nothing" do
      convo = create(:conversation)
      seed_event(convo, position: 1, text: "totally unrelated content")

      result = search("search conversations for zzflarp")

      expect(payload_of(result)["text"]).to eq(Pito::Copy.render("pito.copy.games.list_filter_empty"))
    end
  end

  context "pagination" do
    it "caps page 1 at 20 rows and carries string-keyed row data" do
      base_time = Time.current
      21.times do |n|
        convo = create(:conversation)
        seed_event(convo, position: 1, text: "zzflarp entry #{n}", created_at: base_time + n.minutes)
      end

      hits = hits_of(search("search conversations for zzflarp"))

      expect(hits.size).to eq(20)
      expect(hits.first.keys).to match_array(%w[title snippet anchor_event_id conversation_uuid])
    end
  end
end
