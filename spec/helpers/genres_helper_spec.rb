require "rails_helper"

# Phase 27 v2 spec 05 — `GenresHelper#genre_short_name` collapses an
# IGDB-canonical genre name to the short label the spec's locked
# mapping table assigns (RPG, FPS, JRPG, Sim, MOBA, etc). Unknown /
# unmapped names fall through to the canonical name unchanged. Nil /
# blank input returns nil so callers can chain `.presence` or pass the
# result to view helpers without guarding.
RSpec.describe GenresHelper, type: :helper do
  describe "SHORT_NAMES constant" do
    it "is frozen so call sites cannot mutate the table" do
      expect(GenresHelper::SHORT_NAMES).to be_frozen
    end

    it "maps the canonical RPG name to the RPG acronym" do
      expect(GenresHelper::SHORT_NAMES).to include(
        "Role-playing (RPG)" => "RPG"
      )
    end

    it "maps Japanese RPG to the JRPG acronym" do
      expect(GenresHelper::SHORT_NAMES).to include(
        "Japanese Role-Playing Game (JRPG)" => "JRPG"
      )
    end

    it "maps Shooter and First-person Shooter to the FPS acronym" do
      expect(GenresHelper::SHORT_NAMES).to include(
        "Shooter"              => "FPS",
        "First-person Shooter" => "FPS"
      )
    end

    it "maps Simulator to the Sim short label" do
      expect(GenresHelper::SHORT_NAMES).to include("Simulator" => "Sim")
    end

    it "maps MOBA to MOBA (preserving the acronym)" do
      expect(GenresHelper::SHORT_NAMES).to include("MOBA" => "MOBA")
    end

    it "maps Platform to Platformer" do
      expect(GenresHelper::SHORT_NAMES).to include("Platform" => "Platformer")
    end

    it "maps Visual Novel to the VN acronym" do
      expect(GenresHelper::SHORT_NAMES).to include("Visual Novel" => "VN")
    end

    it "maps Card & Board Game to Card" do
      expect(GenresHelper::SHORT_NAMES).to include("Card & Board Game" => "Card")
    end

    it "maps Hack and slash/Beat 'em up to Hack/Slash" do
      expect(GenresHelper::SHORT_NAMES).to include(
        "Hack and slash/Beat 'em up" => "Hack/Slash"
      )
    end

    it "collapses Point-and-click into Adventure" do
      # Per the spec's locked table — both render as `Adventure` on
      # the shelf heading.
      expect(GenresHelper::SHORT_NAMES).to include(
        "Point-and-click" => "Adventure",
        "Adventure"       => "Adventure"
      )
    end

    it "maps RTS to RTS and TBS to TBS (acronym preservation)" do
      expect(GenresHelper::SHORT_NAMES).to include(
        "Real Time Strategy (RTS)"  => "RTS",
        "Turn-based strategy (TBS)" => "TBS"
      )
    end
  end

  describe "#genre_short_name with a String input" do
    it "returns the locked short label for a known IGDB name" do
      expect(helper.genre_short_name("Role-playing (RPG)")).to eq("RPG")
    end

    it "returns FPS for Shooter (the spec's locked mapping)" do
      expect(helper.genre_short_name("Shooter")).to eq("FPS")
    end

    it "returns FPS for First-person Shooter (the spec's locked mapping)" do
      expect(helper.genre_short_name("First-person Shooter")).to eq("FPS")
    end

    it "returns JRPG for Japanese Role-Playing Game (JRPG)" do
      expect(helper.genre_short_name("Japanese Role-Playing Game (JRPG)")).to eq("JRPG")
    end

    it "returns Sim for Simulator" do
      expect(helper.genre_short_name("Simulator")).to eq("Sim")
    end

    it "returns MOBA for MOBA" do
      expect(helper.genre_short_name("MOBA")).to eq("MOBA")
    end

    it "returns Platformer for Platform" do
      expect(helper.genre_short_name("Platform")).to eq("Platformer")
    end

    it "returns Adventure unchanged for the one-to-one Adventure mapping" do
      expect(helper.genre_short_name("Adventure")).to eq("Adventure")
    end

    it "returns the IGDB canonical name unchanged for an unmapped genre" do
      expect(helper.genre_short_name("Pumpkin Spice Latte"))
        .to eq("Pumpkin Spice Latte")
    end
  end

  describe "#genre_short_name with a Genre instance" do
    it "reads the genre's name and looks it up in the mapping" do
      genre = build(:genre, name: "Role-playing (RPG)")
      expect(helper.genre_short_name(genre)).to eq("RPG")
    end

    it "returns the canonical name when the genre's name is unmapped" do
      genre = build(:genre, name: "Pumpkin Spice Latte")
      expect(helper.genre_short_name(genre)).to eq("Pumpkin Spice Latte")
    end

    it "works on a persisted Genre record" do
      genre = create(:genre, name: "Visual Novel", igdb_id: 9_001)
      expect(helper.genre_short_name(genre)).to eq("VN")
    end
  end

  describe "#genre_short_name edge cases" do
    it "returns nil when the input is nil" do
      expect(helper.genre_short_name(nil)).to be_nil
    end

    it "returns nil when the input is an empty string" do
      expect(helper.genre_short_name("")).to be_nil
    end

    it "returns nil when the genre's name is blank" do
      genre = Genre.new(name: "")
      expect(helper.genre_short_name(genre)).to be_nil
    end

    it "returns nil when the genre's name is nil" do
      genre = Genre.new(name: nil)
      expect(helper.genre_short_name(genre)).to be_nil
    end

    it "coerces non-string non-Genre input via #to_s and looks up the result" do
      expect(helper.genre_short_name(:Adventure)).to eq("Adventure")
    end
  end
end
