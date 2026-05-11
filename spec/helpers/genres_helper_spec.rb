require "rails_helper"

# Phase 27 follow-up — short-form display map for IGDB genre names
# in `/games` shelves and listing-layer chrome. The helper is purely
# cosmetic: the URL slug and the underlying `Genre` record stay
# canonical. Game show / edit pages keep the long name.
RSpec.describe GenresHelper, type: :helper do
  describe "GENRE_SHORT_NAMES constant" do
    it "is frozen so call sites cannot mutate the table" do
      expect(GenresHelper::GENRE_SHORT_NAMES).to be_frozen
    end

    it "covers the documented long-form names" do
      # Both spellings of the FPS / MMO names IGDB has shipped over
      # time are mapped — the helper is forgiving of either form so
      # a future IGDB rename does not silently regress the shelf.
      expect(GenresHelper::GENRE_SHORT_NAMES).to include(
        "Role-playing (RPG)"                 => "RPG",
        "Real Time Strategy (RTS)"           => "RTS",
        "Turn-based strategy (TBS)"          => "TBS",
        "Massively Multiplayer Online"       => "MMO",
        "Massively Multiplayer Online (MMO)" => "MMO",
        "First-person shooter"               => "FPS",
        "First-person Shooter"               => "FPS",
        "Hack and slash/Beat 'em up"         => "Hack & Slash",
        "Card & Board Game"                  => "Card / Board",
        "Quiz/Trivia"                        => "Trivia",
        "Visual Novel"                       => "VN"
      )
    end
  end

  describe "#genre_short_name" do
    context "with a known long-form name (string)" do
      it "maps 'Role-playing (RPG)' to 'RPG'" do
        expect(helper.genre_short_name("Role-playing (RPG)")).to eq("RPG")
      end

      it "maps 'Real Time Strategy (RTS)' to 'RTS'" do
        expect(helper.genre_short_name("Real Time Strategy (RTS)")).to eq("RTS")
      end

      it "maps 'Turn-based strategy (TBS)' to 'TBS'" do
        expect(helper.genre_short_name("Turn-based strategy (TBS)")).to eq("TBS")
      end

      it "maps 'Massively Multiplayer Online' to 'MMO'" do
        expect(helper.genre_short_name("Massively Multiplayer Online")).to eq("MMO")
      end

      it "maps the parenthesized MMO spelling to 'MMO' as well" do
        expect(
          helper.genre_short_name("Massively Multiplayer Online (MMO)")
        ).to eq("MMO")
      end

      it "maps both case spellings of First-person shooter to 'FPS'" do
        expect(helper.genre_short_name("First-person shooter")).to eq("FPS")
        expect(helper.genre_short_name("First-person Shooter")).to eq("FPS")
      end

      it "maps 'Hack and slash/Beat \\'em up' to 'Hack & Slash'" do
        expect(
          helper.genre_short_name("Hack and slash/Beat 'em up")
        ).to eq("Hack & Slash")
      end

      it "maps 'Card & Board Game' to 'Card / Board'" do
        expect(helper.genre_short_name("Card & Board Game")).to eq("Card / Board")
      end

      it "maps 'Quiz/Trivia' to 'Trivia'" do
        expect(helper.genre_short_name("Quiz/Trivia")).to eq("Trivia")
      end

      it "maps 'Visual Novel' to 'VN'" do
        expect(helper.genre_short_name("Visual Novel")).to eq("VN")
      end
    end

    context "with a known long-form name (Genre instance)" do
      it "reads the model's #name and returns the short form" do
        genre = build(:genre, name: "Role-playing (RPG)")
        expect(helper.genre_short_name(genre)).to eq("RPG")
      end

      it "works on a persisted Genre record" do
        genre = create(:genre, name: "Visual Novel", igdb_id: 9_001)
        expect(helper.genre_short_name(genre)).to eq("VN")
      end
    end

    context "with an unknown name" do
      it "returns the full string as-is" do
        expect(helper.genre_short_name("Adventure")).to eq("Adventure")
      end

      it "returns the full Genre#name as-is" do
        genre = build(:genre, name: "Puzzle")
        expect(helper.genre_short_name(genre)).to eq("Puzzle")
      end

      it "is case-sensitive — variant spellings not in the map pass through" do
        # "role-playing (rpg)" lowercase isn't a key; verifies the
        # helper does not coerce on case. Adding lowercase forms to
        # the map later is a non-breaking change.
        expect(helper.genre_short_name("role-playing (rpg)")).to eq("role-playing (rpg)")
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
        # Symbols are not standard but the helper should not raise.
        # `:Adventure.to_s` → "Adventure", which is not in the map,
        # so the helper returns "Adventure".
        expect(helper.genre_short_name(:Adventure)).to eq("Adventure")
      end
    end
  end
end
