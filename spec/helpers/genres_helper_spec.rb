require "rails_helper"

# Phase 27 follow-up (2026-05-11) — display-label helper for IGDB
# genre names in `/games` shelves and listing-layer chrome.
#
# Convention: pito copy is lowercase EXCEPT brand names and explicit
# acronyms. So "Adventure" reads "adventure", "Shooter" → "shooter",
# "Role-playing (RPG)" → "RPG" (acronym preserved). The helper is
# purely cosmetic: the URL slug and the underlying `Genre` record stay
# canonical. Game show / edit pages keep the long name.
RSpec.describe GenresHelper, type: :helper do
  describe "GENRE_SHORT_NAMES constant" do
    it "is frozen so call sites cannot mutate the table" do
      expect(GenresHelper::GENRE_SHORT_NAMES).to be_frozen
    end

    it "covers the long-form acronym names" do
      expect(GenresHelper::GENRE_SHORT_NAMES).to include(
        "Role-playing (RPG)"                 => "RPG",
        "Real Time Strategy (RTS)"           => "RTS",
        "Turn-based strategy (TBS)"          => "TBS",
        "Massively Multiplayer Online"       => "MMO",
        "Massively Multiplayer Online (MMO)" => "MMO"
      )
    end

    it "drops the legacy 'First-person shooter' → 'FPS' mapping" do
      # User direction 2026-05-11 — "shooter is shooter actually".
      # The lowercase rule handles 'Shooter' / 'First-person Shooter'
      # generically; no per-name mapping needed.
      expect(GenresHelper::GENRE_SHORT_NAMES).not_to have_key("First-person shooter")
      expect(GenresHelper::GENRE_SHORT_NAMES).not_to have_key("First-person Shooter")
    end
  end

  describe "ACRONYM_LABELS constant" do
    it "is frozen" do
      expect(GenresHelper::ACRONYM_LABELS).to be_frozen
    end

    it "only contains 'RPG' for now" do
      expect(GenresHelper::ACRONYM_LABELS).to eq(%w[RPG])
    end
  end

  describe "#genre_short_name" do
    context "with a known long-form name (string)" do
      it "maps 'Role-playing (RPG)' to 'RPG' (acronym preserved)" do
        expect(helper.genre_short_name("Role-playing (RPG)")).to eq("RPG")
      end

      it "maps 'Real Time Strategy (RTS)' to lowercase 'rts'" do
        # RTS is in the short-name map but NOT in ACRONYM_LABELS, so
        # the lowercase rule applies (only RPG stays upper per the
        # locked 2026-05-11 direction). Extending ACRONYM_LABELS later
        # to include RTS / MMO is a non-breaking change.
        expect(helper.genre_short_name("Real Time Strategy (RTS)")).to eq("rts")
      end

      it "maps 'Massively Multiplayer Online' to 'mmo' (lowercase rule)" do
        expect(helper.genre_short_name("Massively Multiplayer Online")).to eq("mmo")
      end

      it "maps 'Visual Novel' to 'visual novel' (lowercase rule)" do
        expect(helper.genre_short_name("Visual Novel")).to eq("visual novel")
      end

      it "maps 'Hack and slash/Beat \\'em up' to 'hack & slash' (lowercased)" do
        expect(helper.genre_short_name("Hack and slash/Beat 'em up")).to eq("hack & slash")
      end
    end

    context "lowercase rule for unmapped names" do
      it "downcases 'Adventure' to 'adventure'" do
        expect(helper.genre_short_name("Adventure")).to eq("adventure")
      end

      it "downcases 'Shooter' to 'shooter'" do
        expect(helper.genre_short_name("Shooter")).to eq("shooter")
      end

      it "downcases 'First-person Shooter' to 'first-person shooter'" do
        # The legacy FPS mapping was dropped per user direction. The
        # lowercase rule applies uniformly.
        expect(helper.genre_short_name("First-person Shooter")).to eq("first-person shooter")
      end

      it "downcases 'Puzzle' to 'puzzle'" do
        expect(helper.genre_short_name("Puzzle")).to eq("puzzle")
      end

      it "leaves an already-lowercase name unchanged" do
        expect(helper.genre_short_name("indie")).to eq("indie")
      end
    end

    context "with a Genre model instance" do
      it "reads the model's #name and applies the rule" do
        genre = build(:genre, name: "Adventure")
        expect(helper.genre_short_name(genre)).to eq("adventure")
      end

      it "honors the acronym list when the model's name resolves to RPG" do
        genre = build(:genre, name: "Role-playing (RPG)")
        expect(helper.genre_short_name(genre)).to eq("RPG")
      end

      it "works on a persisted Genre record" do
        genre = create(:genre, name: "Visual Novel", igdb_id: 9_001)
        expect(helper.genre_short_name(genre)).to eq("visual novel")
      end
    end

    context "with nil or blank input" do
      it "returns nil for nil" do
        expect(helper.genre_short_name(nil)).to be_nil
      end

      it "returns nil for an empty string" do
        expect(helper.genre_short_name("")).to be_nil
      end

      it "returns nil for a Genre whose #name is nil" do
        genre = Genre.new(name: nil)
        expect(helper.genre_short_name(genre)).to be_nil
      end

      it "returns nil for a Genre whose #name is the empty string" do
        genre = Genre.new(name: "")
        expect(helper.genre_short_name(genre)).to be_nil
      end
    end

    context "with non-string, non-Genre input" do
      it "coerces via #to_s and looks up the result" do
        # `:Adventure.to_s` → "Adventure" → lowercase rule → "adventure".
        expect(helper.genre_short_name(:Adventure)).to eq("adventure")
      end
    end
  end
end
