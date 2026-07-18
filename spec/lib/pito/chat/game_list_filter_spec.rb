# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::GameListFilter do
  # Helper to build a handler result for a given raw command.
  def handler_for(raw)
    Pito::Chat::Handlers::List.new(
      message:      Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw:),
      conversation: Conversation.singleton
    )
  end

  def result_titles(raw)
    result = handler_for(raw).call
    return [] unless result.is_a?(Pito::Chat::Result::Ok)

    # `list games upcoming` emits a PAIR (:system soon + :enhanced later), so
    # aggregate table rows across every event. Game-list rows use the kv-table
    # :cells form — title is the 2nd cell.
    result.events
      .flat_map { |e| Array(e[:payload]["table_rows"]) }
      .map { |r| r[:cells][1][:text] }
  end

  # ── Fixtures ──────────────────────────────────────────────────────────────

  let!(:ps5_game) do
    create(:game, title: "Demon's Souls", platforms: [ "PlayStation 5" ])
  end

  let!(:ps4_game) do
    create(:game, title: "Bloodborne", platforms: [ "PlayStation 4" ])
  end

  let!(:pc_game) do
    create(:game, title: "Hades", platforms: [ "PC (Microsoft Windows)" ])
  end

  let!(:multi_game) do
    create(:game, title: "Elden Ring", platforms: [ "PlayStation 5", "Xbox Series X|S", "PC (Microsoft Windows)" ])
  end

  let!(:rpg_genre)    { create(:genre, name: "Role-playing (RPG)") }
  let!(:action_genre) { create(:genre, name: "Action") }
  let!(:shooter_genre) { create(:genre, name: "Shooter") }

  let!(:rpg_game) do
    g = create(:game, title: "Baldur's Gate 3", platforms: [ "PC (Microsoft Windows)" ])
    create(:game_genre, game: g, genre: rpg_genre)
    g
  end

  let!(:action_game) do
    g = create(:game, title: "Devil May Cry 5", platforms: [ "PlayStation 5" ])
    create(:game_genre, game: g, genre: action_genre)
    g
  end

  let!(:shooter_game) do
    g = create(:game, title: "Returnal", platforms: [ "PlayStation 5" ])
    create(:game_genre, game: g, genre: shooter_genre)
    g
  end

  let!(:upcoming_ps_game) do
    create(:game, :unreleased, title: "Future PS Game", platforms: [ "PlayStation 5" ])
  end

  let!(:upcoming_rpg_game) do
    g = create(:game, :unreleased, title: "Future RPG", platforms: [ "PlayStation 5" ])
    create(:game_genre, game: g, genre: rpg_genre)
    g
  end

  let!(:released_rpg_ps_game) do
    g = create(:game, title: "Final Fantasy XVI", platforms: [ "PlayStation 5" ],
                      release_year: 2023, release_month: 6, release_day: 22)
    create(:game_genre, game: g, genre: rpg_genre)
    g
  end

  # ── No-filter baseline ────────────────────────────────────────────────────

  describe "no filters" do
    it "`list` returns all games" do
      titles = result_titles("list")
      expect(titles).to include(ps5_game.title, ps4_game.title, pc_game.title, rpg_game.title)
    end

    it "`list games` returns all games" do
      titles = result_titles("list games")
      expect(titles).to include(ps5_game.title, ps4_game.title, rpg_game.title)
    end
  end

  # ── Platform filtering ────────────────────────────────────────────────────

  describe "platform filter" do
    context "with `ps`" do
      it "returns games on PlayStation 5" do
        expect(result_titles("list games ps")).to include(ps5_game.title)
      end

      it "returns games on PlayStation 4" do
        expect(result_titles("list games ps")).to include(ps4_game.title)
      end

      it "does not return PC-only games" do
        expect(result_titles("list games ps")).not_to include(pc_game.title)
      end

      it "also returns multi-platform games that have a PlayStation entry" do
        expect(result_titles("list games ps")).to include(multi_game.title)
      end
    end

    context "with `playstation`" do
      it "matches both PS4 and PS5 games (synonym parity with `ps`)" do
        ps_titles      = result_titles("list games ps")
        playstation_titles = result_titles("list games playstation")
        expect(playstation_titles.sort).to eq(ps_titles.sort)
      end
    end

    context "with `ps5`" do
      it "returns only PlayStation 5 games" do
        titles = result_titles("list games ps5")
        expect(titles).to include(ps5_game.title)
        expect(titles).not_to include(ps4_game.title)
      end
    end

    context "with `ps4`" do
      it "returns only PlayStation 4 games" do
        titles = result_titles("list games ps4")
        expect(titles).to include(ps4_game.title)
        expect(titles).not_to include(ps5_game.title)
      end
    end

    context "with `pc`" do
      it "returns PC games" do
        expect(result_titles("list games pc")).to include(pc_game.title)
      end

      it "does not return ps5-only games" do
        expect(result_titles("list games pc")).not_to include(ps5_game.title)
      end
    end

    context "with `xbox`" do
      it "returns multi-platform games that include Xbox" do
        expect(result_titles("list games xbox")).to include(multi_game.title)
      end

      it "excludes PS5-only games" do
        expect(result_titles("list games xbox")).not_to include(ps5_game.title)
      end
    end

    context "with `sony` (v1.6 unified vocab: PlayStation family)" do
      it "matches both PS4 and PS5 games (parity with `ps`)" do
        expect(result_titles("list games sony").sort).to eq(result_titles("list games ps").sort)
      end
    end

    context "with `series x` (bigram token from the unified vocab)" do
      it "returns only Xbox Series X games" do
        xsx_game = create(:game, title: "Series X Only", platforms: [ "Xbox Series X" ])
        titles   = result_titles("list games series x")
        expect(titles).to include(xsx_game.title)
        expect(titles).not_to include(ps5_game.title)
      end
    end

    context "with `arcade` (dropped from the vocab — owner v1.4.0)" do
      it "is no longer recognized vocabulary" do
        expect(described_class.recognized?("arcade")).to be false
      end

      it "is an unknown token to the list handler (no-guess: no silent list-everything)" do
        expect(result_titles("list games arcade")).to be_empty
      end
    end
  end

  # ── Genre filtering ───────────────────────────────────────────────────────

  describe "genre filter" do
    it "`rpg` returns RPG games" do
      titles = result_titles("list games rpg")
      expect(titles).to include(rpg_game.title)
    end

    it "`rpg` does not return non-RPG games" do
      expect(result_titles("list games rpg")).not_to include(pc_game.title)
    end

    it "`shooter` returns Shooter games" do
      expect(result_titles("list games shooter")).to include(shooter_game.title)
    end

    it "`action` returns Action genre games" do
      expect(result_titles("list games action")).to include(action_game.title)
    end

    it "multiple genre tokens are ORed (rpg OR action)" do
      titles = result_titles("list games rpg action")
      expect(titles).to include(rpg_game.title)
      expect(titles).to include(action_game.title)
    end
  end

  # ── Upcoming filter ───────────────────────────────────────────────────────

  describe "upcoming filter" do
    it "`list games upcoming` returns only upcoming games" do
      titles = result_titles("list games upcoming")
      expect(titles).to include(upcoming_ps_game.title, upcoming_rpg_game.title)
    end

    it "`list games upcoming` excludes already-released games" do
      # ps5_game has no release_date set so it actually qualifies as upcoming
      # (release_year IS NULL). Only released_rpg_ps_game has a past date.
      titles = result_titles("list games upcoming")
      expect(titles).not_to include(released_rpg_ps_game.title)
    end
  end

  # ── Combined filters ──────────────────────────────────────────────────────

  describe "combined filters (AND across types, OR within type)" do
    it "`upcoming rpg ps` returns upcoming RPG games on PlayStation" do
      titles = result_titles("list games upcoming rpg ps")
      expect(titles).to include(upcoming_rpg_game.title)
    end

    it "`upcoming rpg ps` excludes released RPG PS games" do
      expect(result_titles("list games upcoming rpg ps")).not_to include(released_rpg_ps_game.title)
    end

    it "`upcoming rpg ps` excludes upcoming PS games without the RPG genre" do
      expect(result_titles("list games upcoming rpg ps")).not_to include(upcoming_ps_game.title)
    end

    it "order-independence: `ps upcoming rpg` == `rpg ps upcoming`" do
      titles_a = result_titles("list games ps upcoming rpg")
      titles_b = result_titles("list games rpg ps upcoming")
      expect(titles_a.sort).to eq(titles_b.sort)
    end

    it "order-independence: `list games rpg ps upcoming` == `list games upcoming rpg ps`" do
      expect(result_titles("list games rpg ps upcoming").sort)
        .to eq(result_titles("list games upcoming rpg ps").sort)
    end
  end

  # ── Empty-state ───────────────────────────────────────────────────────────

  describe "empty filtered result" do
    it "returns the filter-specific empty copy when filters yield nothing" do
      result = handler_for("list games switch rpg").call
      payload = result.events.first[:payload]
      # No games on Nintendo Switch with RPG genre in our test data.
      expect(payload["text"]).to be_present
      expect(payload["table_rows"]).to be_nil
    end

    it "filter empty copy is distinct from the library-empty copy" do
      # Library empty copy key: pito.copy.games.list_empty (no games at all)
      # Filter empty copy key: pito.copy.games.list_filter_empty
      filter_text = Pito::Copy.render("pito.copy.games.list_filter_empty")
      library_empty_text = Pito::Copy.render("pito.copy.games.list_empty")
      expect(filter_text).not_to eq(library_empty_text)
    end
  end

  # ── Default id-DESC ordering ──────────────────────────────────────────────
  #
  # GameListFilter.call always bases its relation on ::Game.order(id: :desc).
  # Verify this by creating two games where title-ASC would give the reverse
  # order — the higher-id game must appear first in the result regardless of
  # where its title falls alphabetically.

  describe "default id-DESC ordering" do
    # first_game is created before second_game → it has the lower database id.
    # Title-ASC would put "AAA" first; id-DESC must put "ZZZ" first instead.
    let!(:first_game)  { create(:game, title: "AAA First Created") }
    let!(:second_game) { create(:game, title: "ZZZ Second Created") }

    it "lists games with the highest id first (id DESC) by default" do
      titles = result_titles("list games")
      expect(titles.index("ZZZ Second Created")).to be < titles.index("AAA First Created")
    end
  end

  # ── Allowlist: arbitrary filler is dropped, recognized tokens kept ─────────

  # The SERVICE-level allowlist: GameListFilter.call drops unrecognised tokens and
  # applies the recognised filters. (The list HANDLER, separately, now rejects a
  # genuinely-unknown word with a `huh` error — owner 2026-06-29's no-guess rule;
  # that handler behaviour is covered in list_spec. These assert the filter engine
  # itself, called directly, still tolerates filler when handed a raw string.)
  describe "allowlist tokenisation (service-level)" do
    it "drops conversational filler and still applies the recognized filter" do
      # 'thanks'/'please'/'yo' are not vocabulary → dropped; 'ps' still filters.
      titles = described_class.call("list games ps please thanks yo").map(&:title)
      expect(titles).to include(ps5_game.title, ps4_game.title)
      expect(titles).not_to include(pc_game.title)
    end

    it "drops a truly-unknown token (close to nothing) and keeps the full set" do
      # 'garbled' is not fuzzy-close to any term → pure filler, not a rejection.
      expect(described_class.call("list games garbled").map(&:title)).to include(ps5_game.title, pc_game.title)
    end
  end

  # ── Did-you-mean: near-miss tokens surface a correction ────────────────────

  describe ".suggestions" do
    it "suggests the genre alias for a close typo (`rpgg` → `rpg`)" do
      expect(described_class.suggestions("list rpgg")).to eq([ "rpg" ])
    end

    it "suggests the platform synonym for a close typo (`playstaton` → `playstation`)" do
      expect(described_class.suggestions("list playstaton")).to include("playstation")
    end

    it "suggests `switch` for `swith`" do
      expect(described_class.suggestions("list swith")).to eq([ "switch" ])
    end

    it "returns nothing for recognized tokens" do
      expect(described_class.suggestions("list games upcoming rpg ps5")).to be_empty
    end

    it "returns nothing for short tokens (avoids false positives like `me`/`yo`)" do
      expect(described_class.suggestions("list games me yo please")).to be_empty
    end

    it "returns nothing for a token that is close to nothing" do
      expect(described_class.suggestions("list garbled")).to be_empty
    end

    it "de-duplicates and preserves order across multiple near-misses" do
      expect(described_class.suggestions("list rpgg rpgg")).to eq([ "rpg" ])
    end

    it "corrects multiple DISTINCT near-misses in one command" do
      # 'rpgg'→'rpg' (genre, d=1) and 'shooterr'→'shooter' (genre, d=1).
      expect(described_class.suggestions("list rpgg shooterr")).to include("rpg", "shooter")
    end

    # ── F-3 (live 2026-07-18): short tokens get a tighter budget ─────────────
    # Production audit: 14 "did you mean" events, repeat offender "hard" →
    # "hack" (Levenshtein 2 on a 4-char token) — the owner typed "list hard
    # games" wanting a difficulty search. Short (<= 4 char) tokens now need
    # distance <= 1; longer tokens keep the pre-existing distance-2 rule.
    # Both sides of the boundary are pinned below.

    it "no longer suggests `hack` for the 4-char token `hard` (distance 2 — the prod false-positive)" do
      expect(described_class.suggestions("list hard")).to be_empty
    end

    it "still suggests within distance 1 on a short (4-char) token (`fpss` → `fps`)" do
      expect(described_class.suggestions("list fpss")).to eq([ "fps" ])
    end

    it "still allows distance 2 on a longer (5+ char) token (`actoin` → `action`, unchanged rule)" do
      expect(described_class.suggestions("list actoin")).to eq([ "action" ])
    end
  end
end
