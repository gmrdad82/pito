# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `analyze` (recognition only, DB mocked) ───────────────────
#
# RULE: every kwarg combination is recognized — no exception. We test what the
# dispatcher UNDERSTANDS, not what exists: all DB lookups are stubbed so the
# resolver "finds" exactly what was requested, and we assert the parsed scope
# (level + entity ids / count), per docs/claude/0.8.0.md §D.
#
# Recognition engine = Pito::Analytics::ScopeResolver (raw + shift+tab scope →
# {status, level, scopes}). The handler is a thin wrapper over it.
RSpec.describe "Dispatch matrix — analyze (recognition, DB mocked)", type: :dispatch do
  def resolve(raw, scope: "@all")
    Pito::Analytics::ScopeResolver.call(raw: raw, channel_scope: scope)
  end

  def ids_of(result) = result.scopes.map(&:id)

  # Default: every lookup succeeds, returning doubles for exactly what was asked.
  before do
    allow(::Video).to   receive(:where) { |a| double(to_a: Array(a[:id]).map { |i| double(id: i) }) }
    allow(::Game).to    receive(:where) { |a| double(to_a: Array(a[:id]).map { |i| double(id: i) }) }
    allow(::Channel).to receive(:find_by).and_return(double(id: 7, at_handle: "@x", handle: "@x"))
    allow(::Channel).to receive(:all).and_return(double(to_a: [ double(id: 1), double(id: 2) ]))
    # bare `analyze games` → shift+tab channels → linked games (chained query)
    allow(::Game).to receive(:joins).and_return(
      double(where: double(distinct: double(to_a: [ double(id: 1), double(id: 2) ])))
    )
  end

  # ── bare analyze → suggest (no entity, no-op) ───────────────────────────────
  describe "bare → suggest" do
    [ "analyze", "stats", "analytics", "analyze   " ].each do |raw|
      it "#{raw.inspect} → suggest (no level, no scopes)" do
        r = resolve(raw)
        expect(r).to be_suggest
        expect(r.level).to be_nil
        expect(r.scopes).to be_empty
      end
    end
  end

  # ── noun → level (channel/vid/game + every alias) ───────────────────────────
  describe "entity noun → level" do
    {
      # bare vids/video(s) == analyze channel (6d) → :channel level
      "analyze channel"  => :channel,
      "analyze channels" => :channel,
      "analyze vids"     => :channel,
      "analyze vid"      => :channel,
      "analyze video"    => :channel,
      "analyze videos"   => :channel
    }.each do |raw, level|
      it "#{raw.inspect} → level #{level}" do
        expect(resolve(raw)).to have_attributes(status: :ok, level: level)
      end
    end

    it "analyze games (bare) → :game (via shift+tab channels → linked games)" do
      expect(resolve("analyze games")).to have_attributes(status: :ok, level: :game)
    end
  end

  # ── analyze vids #ids → :vid, those ids (every id form) ─────────────────────
  describe "vids #id targeting" do
    {
      "analyze vids #1"       => [ 1 ],
      "analyze vids #1,#2"    => [ 1, 2 ],
      "analyze vids #1, #2"   => [ 1, 2 ],
      "analyze vids #1 #2"    => [ 1, 2 ],
      "analyze vids 1,2"      => [ 1, 2 ],     # bare digits
      "analyze vid #5"        => [ 5 ],
      "analyze video #5"      => [ 5 ],
      "analyze videos #5,#6"  => [ 5, 6 ]
    }.each do |raw, ids|
      it "#{raw.inspect} → :vid, ids #{ids.inspect}" do
        r = resolve(raw)
        expect(r).to have_attributes(status: :ok, level: :vid)
        expect(ids_of(r)).to eq(ids)
      end
    end

    it "ids win over shift+tab scope" do
      expect(resolve("analyze vids #9", scope: "@pito")).to have_attributes(level: :vid)
      expect(ids_of(resolve("analyze vids #9", scope: "@pito"))).to eq([ 9 ])
    end
  end

  # ── analyze games #ids → :game, those ids ───────────────────────────────────
  describe "games #id targeting" do
    {
      "analyze games #1,#2" => [ 1, 2 ],
      "analyze game #3"     => [ 3 ],
      "analyze games #3 #4" => [ 3, 4 ]
    }.each do |raw, ids|
      it "#{raw.inspect} → :game, ids #{ids.inspect}" do
        r = resolve(raw)
        expect(r).to have_attributes(status: :ok, level: :game)
        expect(ids_of(r)).to eq(ids)
      end
    end
  end

  # ── channel @handle scoping (explicit handles ignore shift+tab) ─────────────
  describe "channel @handle scoping" do
    it "analyze channel @h → that one channel" do
      r = resolve("analyze channel @pito")
      expect(r).to have_attributes(status: :ok, level: :channel)
      expect(r.scopes.size).to eq(1)
    end

    {
      "analyze channels @a,@b"  => 2,
      "analyze channels @a @b"  => 2,
      "analyze channels @a,@b,@c" => 3
    }.each do |raw, count|
      it "#{raw.inspect} → #{count} channels" do
        expect(resolve(raw).scopes.size).to eq(count)
      end
    end
  end

  # ── shift+tab scope (bare channel/vids) ─────────────────────────────────────
  describe "shift+tab channel scope (bare)" do
    it "bare channel @all → all channels" do
      r = resolve("analyze channel", scope: "@all")
      expect(r).to have_attributes(status: :ok, level: :channel)
      expect(r.scopes.size).to eq(2)
    end

    it "bare channel @handle → that channel" do
      r = resolve("analyze channel", scope: "@pito")
      expect(r).to have_attributes(status: :ok, level: :channel)
      expect(r.scopes.size).to eq(1)
    end

    it "bare vids @handle → :channel scope (6d)" do
      expect(resolve("analyze vids", scope: "@pito")).to have_attributes(status: :ok, level: :channel)
    end
  end

  # ── error recognition (parsed, but the requested entity isn't found) ────────
  describe "not-found → error (still recognized the intent)" do
    it "vids #ids none found → :vids_not_found" do
      allow(::Video).to receive(:where).and_return(double(to_a: []))
      expect(resolve("analyze vids #1,#2")).to have_attributes(status: :error, error_key: :vids_not_found)
    end

    it "games #ids none found → :games_not_found" do
      allow(::Game).to receive(:where).and_return(double(to_a: []))
      expect(resolve("analyze games #9")).to have_attributes(status: :error, error_key: :games_not_found)
    end

    it "channels @handle not found → :channels_not_found" do
      allow(::Channel).to receive(:find_by).and_return(nil)
      expect(resolve("analyze channels @nope")).to have_attributes(status: :error, error_key: :channels_not_found)
    end

    it "bare channel with unknown shift+tab handle → :channel_not_found" do
      allow(::Channel).to receive(:find_by).and_return(nil)
      expect(resolve("analyze channel", scope: "@nope")).to have_attributes(status: :error, error_key: :channel_not_found)
    end
  end

  # ── Segment selection: which card(s) the analyze handler emits ────────────────
  #
  # Calls Pito::Chat::Handlers::Analyze directly (not ScopeResolver in isolation).
  # Pito::MessageBuilder::Analyze::Message.pair is stubbed to return lightweight
  # events keyed only by role so no ViewComponent or i18n infrastructure is
  # exercised — the assertion target is which roles reach pair, not what renders.
  #
  # Segment names for analyze (all entities share the same two):
  #   "numbers"    → :system  (default — emitted by a bare analyze)
  #   "breakdowns" → :enhanced
  #
  # Metric tokens (e.g. `views`, `comms`) feed MetricSelection.parse on the same
  # raw string; SegmentSelection receives them as extra_vocabulary so they are
  # silently skipped rather than reported as unknown segments.

  describe "segment selection" do
    VID_ID  = 5
    CHAN_ID = 7   # matches the Channel.find_by stub in the outer before block

    let(:conversation) { double("Conversation", stats_period: "28d", scope_channel: "@all") }

    before do
      # scope_title calls entity_title → entity.title for non-channel records;
      # re-stub Video doubles to respond to .title so the handler doesn't blow up.
      allow(::Video).to receive(:where) { |a|
        double(to_a: Array(a[:id]).map { |i| double(id: i, title: "vid #{i}") })
      }

      # Stub pair to return predictable {kind:, payload:} events without touching
      # ViewComponent / i18n / FollowUp.  roles: kwarg is set by roles_for(selection.names)
      # inside the handler — this lets the segment logic run for real.
      allow(Pito::MessageBuilder::Analyze::Message).to receive(:pair) do |**kwargs|
        role_kinds = Pito::MessageBuilder::Analyze::Message::ROLE_KINDS
        Array(kwargs[:roles] || Pito::MessageBuilder::Analyze::Message::ROLES).map do |role|
          { kind: role_kinds.fetch(role), payload: { "analyze" => { "role" => role } } }
        end
      end
    end

    # Build and call an Analyze handler from a raw string (free-chat path).
    def call_analyze(raw)
      parts       = raw.strip.split(/\s+/)
      body_words  = parts[1..]
      body_tokens = body_words.each_with_index.map do |w, i|
        Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
      end
      msg = Pito::Chat::Message.new(
        tool:        :analyze,
        body_tokens: body_tokens,
        kind:        :new_turn,
        raw:         raw
      )
      Pito::Chat::Handlers::Analyze.new(message: msg, conversation: conversation).call
    end

    # 1. bare (no introducer) → only "numbers" segment → 1 :system event
    it "bare analyze vid #<id> → 1 event, kind :system" do
      result = call_analyze("analyze vid ##{VID_ID}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    # 2. full → both segments → 2 events, :system first then :enhanced
    it "analyze vid #<id> full → 2 events, kinds [:system, :enhanced]" do
      result = call_analyze("analyze vid ##{VID_ID} full")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(2)
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    end

    # 3. only breakdowns → "breakdowns" segment only → 1 :enhanced event
    it "analyze vid #<id> only breakdowns → 1 event, kind :enhanced" do
      result = call_analyze("analyze vid ##{VID_ID} only breakdowns")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(1)
      expect(result.events.first[:kind]).to eq(:enhanced)
    end

    # 4. with breakdowns → default ("numbers") + "breakdowns" → 2 events
    it "analyze vid #<id> with breakdowns → 2 events" do
      result = call_analyze("analyze vid ##{VID_ID} with breakdowns")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(2)
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    end

    # 5. metric token only → extra_vocabulary swallows it; no segment selected
    #    beyond the default → 1 :system event, no error
    it "analyze vid #<id> with views → 1 :system event (metric token, not an unknown segment)" do
      result = call_analyze("analyze vid ##{VID_ID} with views")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    # 6. metric alias + segment mixed → alias silently skipped, segment applied
    #    → 2 events, not an error
    it "analyze vid #<id> with comms,breakdowns → 2 events, not an error" do
      result = call_analyze("analyze vid ##{VID_ID} with comms,breakdowns")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(2)
    end

    # 7. unknown segment token → Result::Error
    it "analyze vid #<id> only bogus-thing → Result::Error (unknown segment)" do
      result = call_analyze("analyze vid ##{VID_ID} only bogus-thing")
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    # 8. conflicting introducers → Result::Error
    it "analyze vid #<id> full only breakdowns → Result::Error (conflict)" do
      result = call_analyze("analyze vid ##{VID_ID} full only breakdowns")
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    # 9. channel-level bare → 1 :system event (channel entity shares ANALYZE_SEGMENTS)
    it "bare analyze channel @handle → 1 :system event" do
      result = call_analyze("analyze channel @pito")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.count).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end
  end
end
