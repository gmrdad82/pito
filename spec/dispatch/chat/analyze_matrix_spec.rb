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
end
