require "rails_helper"
require_relative "../../../app/mcp/tools/game_update_local"

RSpec.describe Mcp::Tools::GameUpdateLocal do
  let!(:game) { create(:game) }

  # Helper — every tool response is a single text content frame
  # carrying pretty-printed JSON. The shared parser keeps the per-test
  # noise down.
  def parse(response)
    JSON.parse(response.content.first[:text])
  end

  it "preview when confirm: no — does not mutate" do
    described_class.call(id: game.id, notes: "hello", confirm: "no")
    expect(game.reload.notes).to be_blank
  end

  it "applies notes / played_at / hours_of_footage_manual with confirm: yes" do
    described_class.call(
      id: game.id, notes: "great game",
      played_at: "2025-01-01",
      hours_of_footage_manual: 5,
      confirm: "yes"
    )
    game.reload
    expect(game.notes).to eq("great game")
    expect(game.played_at.to_s).to eq("2025-01-01")
    expect(game.hours_of_footage_manual).to eq(5)
  end

  it "rejects when no fields supplied" do
    result = described_class.call(id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("no fields")
  end

  it "404s on missing game" do
    result = described_class.call(id: 999_999, notes: "x", confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: game.id, notes: "x", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: game.id, notes: "x", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  # ---------------------------------------------------------------
  # Phase 27 §01g — plural per-platform ownership shape
  # ---------------------------------------------------------------

  describe "platform_owned_ids (Phase 27 §01g)" do
    let!(:ps5)    { create(:platform, name: "PlayStation 5", abbreviation: "PS5") }
    let!(:steam)  { create(:platform, name: "Steam",         abbreviation: "Steam") }
    let!(:switch) { create(:platform, name: "Switch 2",      abbreviation: "Switch 2") }

    # -----------------------------------------------------------
    # Happy paths
    # -----------------------------------------------------------

    it "creates two ownership rows when called with `platform_owned_ids: [a, b]`" do
      result = described_class.call(
        id: game.id,
        platform_owned_ids: [ ps5.id, steam.id ],
        confirm: "yes"
      )

      expect(result.to_h[:isError]).to be_falsey
      expect(game.reload.owned_platforms.map(&:id)).to match_array([ ps5.id, steam.id ])

      body = parse(result)
      expect(body["platform_owned_ids"]).to match_array([ ps5.id, steam.id ])
      # Back-compat scalar — first element of the plural set.
      expect(body["platform_owned_id"]).to eq(body["platform_owned_ids"].first)
    end

    it "shrinks the ownership set when subsequent call sends a smaller array" do
      game.game_platform_ownerships.create!(platform: ps5)
      game.game_platform_ownerships.create!(platform: steam)

      described_class.call(id: game.id, platform_owned_ids: [ ps5.id ], confirm: "yes")
      expect(game.reload.owned_platforms.map(&:id)).to eq([ ps5.id ])
    end

    it "un-owns the game everywhere when `platform_owned_ids: []`" do
      game.game_platform_ownerships.create!(platform: ps5)
      game.game_platform_ownerships.create!(platform: steam)

      described_class.call(id: game.id, platform_owned_ids: [], confirm: "yes")
      expect(game.reload.owned_platforms).to be_empty
    end

    it "auto-wraps the singular legacy form `platform_owned_id: <int>`" do
      result = described_class.call(id: game.id, platform_owned_id: ps5.id, confirm: "yes")

      expect(game.reload.owned_platforms.map(&:id)).to eq([ ps5.id ])
      body = parse(result)
      expect(body["platform_owned_ids"]).to eq([ ps5.id ])
      expect(body["platform_owned_id"]).to eq(ps5.id)
      expect(body).not_to have_key("warning")
    end

    it "de-duplicates `platform_owned_ids: [4, 4]`" do
      described_class.call(id: game.id, platform_owned_ids: [ ps5.id, ps5.id ], confirm: "yes")
      expect(game.reload.game_platform_ownerships.count).to eq(1)
    end

    it "keeps the existing ownership row on idempotent re-sync (no destroy + create churn)" do
      row = game.game_platform_ownerships.create!(platform: ps5)

      described_class.call(id: game.id, platform_owned_ids: [ ps5.id, steam.id ], confirm: "yes")

      expect(GamePlatformOwnership.exists?(row.id)).to be(true)
      expect(game.reload.owned_platforms.map(&:id)).to match_array([ ps5.id, steam.id ])
    end

    # -----------------------------------------------------------
    # Sad paths
    # -----------------------------------------------------------

    it "drops unknown platform_id values and surfaces a warning" do
      result = described_class.call(
        id: game.id,
        platform_owned_ids: [ ps5.id, 999_999 ],
        confirm: "yes"
      )

      expect(result.to_h[:isError]).to be_falsey
      body = parse(result)
      expect(body["platform_owned_ids"]).to eq([ ps5.id ])
      expect(body["warning"]).to include("unknown platform_id")
      expect(body["warning"]).to include("999999")
    end

    it "warns when BOTH singular and plural are supplied; plural wins" do
      result = described_class.call(
        id: game.id,
        platform_owned_id: ps5.id,
        platform_owned_ids: [ steam.id ],
        confirm: "yes"
      )

      body = parse(result)
      expect(body["platform_owned_ids"]).to eq([ steam.id ])
      expect(body["warning"]).to include("plural wins")
      expect(game.reload.owned_platforms.map(&:id)).to eq([ steam.id ])
    end

    it "preview includes the warning when conflict detected at confirm: no" do
      result = described_class.call(
        id: game.id,
        platform_owned_id: ps5.id,
        platform_owned_ids: [ steam.id ],
        confirm: "no"
      )

      body = parse(result)
      expect(body["preview"]).to be(true)
      expect(body["warning"]).to include("plural wins")
      # No write occurred.
      expect(game.reload.owned_platforms).to be_empty
    end

    # -----------------------------------------------------------
    # Edge cases
    # -----------------------------------------------------------

    it "treats singular `platform_owned_id: null` as a no-op (legacy callers)" do
      # Pre-existing ownership shouldn't be wiped just because a legacy
      # caller passed `platform_owned_id: null` to mean "leave alone".
      game.game_platform_ownerships.create!(platform: ps5)

      result = described_class.call(
        id: game.id,
        platform_owned_id: nil,
        notes: "added a note",
        confirm: "yes"
      )

      expect(result.to_h[:isError]).to be_falsey
      expect(game.reload.owned_platforms.map(&:id)).to eq([ ps5.id ])
      expect(game.notes).to eq("added a note")
    end

    it "treats absent ownership keys as 'leave alone' (no wipe)" do
      game.game_platform_ownerships.create!(platform: ps5)
      described_class.call(id: game.id, notes: "n", confirm: "yes")
      expect(game.reload.owned_platforms.map(&:id)).to eq([ ps5.id ])
    end

    it "treats only-bad-ids as un-own (drops to []) and warns" do
      game.game_platform_ownerships.create!(platform: ps5)

      result = described_class.call(
        id: game.id,
        platform_owned_ids: [ 999_998, 999_999 ],
        confirm: "yes"
      )

      body = parse(result)
      expect(body["warning"]).to include("unknown platform_id")
      expect(game.reload.owned_platforms).to be_empty
    end

    # -----------------------------------------------------------
    # Flaw — atomicity + mass-assignment guard
    # -----------------------------------------------------------

    it "rolls back the ownership sync if a mid-transaction failure occurs" do
      game.game_platform_ownerships.create!(platform: ps5)

      # Stub the destroy step to raise after we've started mutating. The
      # transaction guard means the pre-existing PS5 ownership must
      # survive the rollback (no partial state).
      allow_any_instance_of(GamePlatformOwnership).to receive(:destroy!).and_raise(StandardError, "boom")

      expect {
        described_class.call(id: game.id, platform_owned_ids: [ steam.id ], confirm: "yes")
      }.to raise_error(StandardError, "boom")

      expect(game.reload.owned_platforms.map(&:id)).to eq([ ps5.id ])
    end

    it "does not allow arbitrary Game columns to be mass-assigned via the tool" do
      # `additionalProperties: false` on the input schema is the wire-
      # level guard; this spec confirms the Ruby handler also drops
      # unknown attribute keys silently (no smuggling via kwargs).
      result = described_class.call(
        id: game.id,
        notes: "ok",
        title: "ATTEMPTED OVERRIDE",
        igdb_id: 9_999_999,
        confirm: "yes"
      )

      expect(result.to_h[:isError]).to be_falsey
      game.reload
      expect(game.notes).to eq("ok")
      expect(game.title).not_to eq("ATTEMPTED OVERRIDE")
      expect(game.igdb_id).not_to eq(9_999_999)
    end

    # -----------------------------------------------------------
    # Preview shape (confirm: no)
    # -----------------------------------------------------------

    it "preview at confirm: no echoes the requested `platform_owned_ids` and does not write" do
      result = described_class.call(
        id: game.id,
        platform_owned_ids: [ ps5.id, steam.id ],
        confirm: "no"
      )

      body = parse(result)
      expect(body["preview"]).to be(true)
      expect(body["changes"]["platform_owned_ids"]["new"]).to match_array([ ps5.id, steam.id ])
      expect(game.reload.owned_platforms).to be_empty
    end
  end
end
