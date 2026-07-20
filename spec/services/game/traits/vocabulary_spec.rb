# frozen_string_literal: true

require "rails_helper"

# ── Game::Traits::Vocabulary — the config/pito/traits.yml loader ────────────
#
# Mirrors Pito::Achievements::Config's spec style (see
# spec/services/pito/achievements/config_spec.rb): the shipped-file
# assertions read the REAL config/pito/traits.yml through the public API
# (never raw YAML); the LoadError branches swap in a Tempfile fixture via
# `stub_const` + `reload!`. The `around` hook reloads the real config both
# before AND after every example — see that sibling spec's comment for why
# `around` (not `after`) is required to avoid a fixture leaking into a later
# spec once rspec-mocks reverts `stub_const`.
RSpec.describe Game::Traits::Vocabulary do
  around do |example|
    described_class.reload!
    example.run
  ensure
    described_class.reload!
  end

  # A minimal, valid traits vocabulary document — every LoadError-branch test
  # below `.sub`s a unique fragment out of this string.
  VALID_TRAITS_YML = <<~YML
    schema_version: 1
    scales:
      difficulty:
        source: classified
        description: "how hard"
        values: [easy, hard]
    tags:
      space:
        source: classified
        description: "set in space"
      action:
        source: derived
        description: "action-forward"
  YML

  def with_traits_yml(yaml)
    Tempfile.create([ "traits", ".yml" ]) do |f|
      f.write(yaml)
      f.flush
      stub_const("Game::Traits::Vocabulary::PATH", Pathname.new(f.path))
      described_class.reload!
      yield
    end
  end

  # ── The shipped config/pito/traits.yml ───────────────────────────────────
  describe "the shipped config/pito/traits.yml" do
    it ".scale_names lists the scales in declaration order" do
      expect(described_class.scale_names).to eq(%w[difficulty story pace])
    end

    it ".scales exposes each scale's ordered values + source" do
      expect(described_class.scales["difficulty"]).to include(
        "source" => "classified",
        "values" => %w[easy fair hard brutal]
      )
      expect(described_class.scales["pace"]["values"]).to eq(%w[relaxing steady fast chaotic])
    end

    it ".tag_names lists every tag (classified then derived) in declaration order" do
      expect(described_class.tag_names).to eq(%w[
        space skill_based parry_windows frame_tight_jumps immersive realistic flight
        poor_performance worth_it awful game_of_the_year
        soulslike cozy roguelike metroidvania grindy base_building city_builder
        replayable couch_co_op scary_but_fun choices_matter
        platformer simulation guns action horror survival war time_consuming acclaimed
        multiplayer single_player hyped family_friendly
        adventure role_playing open_world racing
      ])
    end

    # Q28/Q29/Q32 additions (2026-07-20 interview): soulslike…choices_matter.
    it ".classified_tag_names returns only source: classified tags" do
      expect(described_class.classified_tag_names).to eq(%w[
        space skill_based parry_windows frame_tight_jumps immersive realistic flight
        poor_performance worth_it awful game_of_the_year
        soulslike cozy roguelike metroidvania grindy base_building city_builder
        replayable couch_co_op scary_but_fun choices_matter
      ])
    end

    # L6 flip (2026-07-17): multiplayer/single_player/hyped/family_friendly
    # moved from classified to derived once game_modes/hypes/age_ratings
    # started syncing (Game::Igdb::Client::GAME_FIELDS). Q32 (2026-07-20):
    # adventure/role_playing/open_world/racing derive from synced genres/themes.
    it ".derived_tag_names returns only source: derived tags" do
      expect(described_class.derived_tag_names).to eq(%w[
        platformer simulation guns action horror survival war time_consuming acclaimed
        multiplayer single_player hyped family_friendly
        adventure role_playing open_world racing
      ])
    end

    describe ".valid_scale_value?" do
      it "is true for a declared member" do
        expect(described_class.valid_scale_value?("difficulty", "brutal")).to be true
      end

      it "is false for a non-member value" do
        expect(described_class.valid_scale_value?("difficulty", "extreme")).to be false
      end

      it "is false (never raises) for an unknown scale" do
        expect(described_class.valid_scale_value?("nonexistent", "brutal")).to be false
      end
    end
  end

  # ── errors_for — THE validator ───────────────────────────────────────────
  describe ".errors_for" do
    it "accepts {} (unclassified)" do
      expect(described_class.errors_for({})).to eq([])
    end

    it "rejects a non-Hash" do
      expect(described_class.errors_for("nope")).to eq([ "must be a Hash" ])
    end

    it "accepts the traits-design.md worked example verbatim" do
      traits = {
        "schema_version" => 1,
        "values" => {
          "difficulty" => "brutal",
          "story" => "catching",
          "pace" => "fast",
          "tags" => %w[skill_based worth_it action time_consuming]
        },
        "sources" => {
          "difficulty" => "classified",
          "story" => "owner",
          "pace" => "classified",
          "skill_based" => "classified",
          "worth_it" => "owner",
          "action" => "derived",
          "time_consuming" => "derived",
          "war" => "owner"
        },
        "classified_at" => "2026-07-17T09:30:00Z"
      }

      expect(described_class.errors_for(traits)).to eq([])
    end

    it "requires schema_version on a non-empty hash" do
      errors = described_class.errors_for("values" => { "difficulty" => "brutal" })
      expect(errors).to include(a_string_matching(/unsupported schema_version nil/))
    end

    # 2 became supported with the Q28-Q32 expansion (2026-07-20) — 99 is the
    # forever-invalid probe, matching spec/models/game_traits_spec.rb.
    it "rejects an unsupported schema_version" do
      errors = described_class.errors_for("schema_version" => 99, "values" => {})
      expect(errors).to include(a_string_matching(/unsupported schema_version 99/))
    end

    it "rejects an unknown top-level key" do
      errors = described_class.errors_for("schema_version" => 1, "bogus" => true)
      expect(errors).to include(a_string_matching(/unknown top-level key\(s\).*bogus/))
    end

    it "rejects a values that isn't a Hash" do
      errors = described_class.errors_for("schema_version" => 1, "values" => "brutal")
      expect(errors).to include("values must be a Hash")
    end

    it "rejects a sources that isn't a Hash" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => [])
      expect(errors).to include("sources must be a Hash")
    end

    it "rejects an unknown scale name in values" do
      errors = described_class.errors_for("schema_version" => 1, "values" => { "spice" => "hot" })
      expect(errors).to include(a_string_matching(/unknown scale "spice" in values/))
    end

    it "rejects a non-member scale value" do
      errors = described_class.errors_for("schema_version" => 1, "values" => { "difficulty" => "extreme" })
      expect(errors).to include(a_string_matching(/"extreme" is not a valid value for scale "difficulty"/))
    end

    it "rejects values.tags that isn't an Array" do
      errors = described_class.errors_for("schema_version" => 1, "values" => { "tags" => "action" })
      expect(errors).to include("values.tags must be an Array")
    end

    it "rejects an unknown tag in values.tags" do
      errors = described_class.errors_for("schema_version" => 1, "values" => { "tags" => %w[not_a_tag] })
      expect(errors).to include(a_string_matching(/unknown tag\(s\) in values\.tags.*not_a_tag/))
    end

    it "rejects a duplicate tag in values.tags" do
      errors = described_class.errors_for("schema_version" => 1, "values" => { "tags" => %w[action action] })
      expect(errors).to include(a_string_matching(/duplicate tag\(s\) in values\.tags.*action/))
    end

    it "rejects an unknown trait name in sources" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "nonexistent" => "owner" })
      expect(errors).to include(a_string_matching(/unknown trait "nonexistent" in sources/))
    end

    it "rejects an invalid source value" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "difficulty" => "wat" })
      expect(errors).to include(a_string_matching(/invalid source "wat" for "difficulty"/))
    end

    it "rejects source: derived on a scale (scales carry only classified/owner)" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "difficulty" => "derived" })
      expect(errors).to include(a_string_matching(/source "derived" not legal for "difficulty"/))
    end

    it "rejects source: classified on a derived-declared tag" do
      errors = described_class.errors_for(
        "schema_version" => 1,
        "values" => { "tags" => %w[action] },
        "sources" => { "action" => "classified" }
      )
      expect(errors).to include(a_string_matching(/source "classified" not legal for "action"/))
    end

    it "rejects source: derived on a classified-declared tag" do
      errors = described_class.errors_for(
        "schema_version" => 1,
        "values" => { "tags" => %w[skill_based] },
        "sources" => { "skill_based" => "derived" }
      )
      expect(errors).to include(a_string_matching(/source "derived" not legal for "skill_based"/))
    end

    it "rejects a classified sources entry for a scale absent from values" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "difficulty" => "classified" })
      expect(errors).to include(a_string_matching(/"difficulty" is absent from values.*only "owner" may pin absence/))
    end

    it "rejects a derived sources entry for a tag absent from values.tags" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "action" => "derived" })
      expect(errors).to include(a_string_matching(/"action" is absent from values.*only "owner" may pin absence/))
    end

    it "accepts an owner sources entry for a scale absent from values (pinned-absent scale)" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "difficulty" => "owner" })
      expect(errors).to eq([])
    end

    it "accepts an owner sources entry for a tag absent from values.tags (pinned-absent tag)" do
      errors = described_class.errors_for("schema_version" => 1, "sources" => { "war" => "owner" })
      expect(errors).to eq([])
    end
  end

  # ── LoadError branches ────────────────────────────────────────────────────
  describe "LoadError branches" do
    it "raises when the file does not exist" do
      Dir.mktmpdir do |dir|
        missing_path = Pathname.new(dir).join("does_not_exist.yml")
        stub_const("Game::Traits::Vocabulary::PATH", missing_path)
        described_class.reload!

        expect { described_class.scales }.to raise_error(LoadError, /#{Regexp.escape(missing_path.to_s)} not found/)
      end
    end

    it "raises on an unsupported schema_version" do
      with_traits_yml(VALID_TRAITS_YML.sub("schema_version: 1", "schema_version: 999")) do
        expect { described_class.scales }.to raise_error(LoadError, /unsupported schema_version 999/)
      end
    end

    it "raises when a name is declared in both scales: and tags:" do
      with_traits_yml(VALID_TRAITS_YML.sub("tags:\n  space:", "tags:\n  difficulty:\n    source: classified\n    description: dupe\n  space:")) do
        expect { described_class.scales }.to raise_error(LoadError, /declared in both scales: and tags:.*difficulty/)
      end
    end

    it "raises when a scale is named \"tags\"" do
      with_traits_yml(VALID_TRAITS_YML.sub("difficulty:", "tags:")) do
        expect { described_class.scales }.to raise_error(LoadError, /a scale cannot be named "tags"/)
      end
    end
  end

  # ── reload! ────────────────────────────────────────────────────────────────
  describe ".reload!" do
    it "memoizes until reload!, then re-reads the file" do
      Tempfile.create([ "traits", ".yml" ]) do |f|
        f.write(VALID_TRAITS_YML)
        f.flush
        stub_const("Game::Traits::Vocabulary::PATH", Pathname.new(f.path))
        described_class.reload!
        expect(described_class.scale_names).to eq(%w[difficulty])

        f.rewind
        f.truncate(0)
        f.write(VALID_TRAITS_YML.sub("  difficulty:", "  pace:"))
        f.flush
        expect(described_class.scale_names).to eq(%w[difficulty]) # still memoized

        described_class.reload!
        expect(described_class.scale_names).to eq(%w[pace]) # re-read
      end
    end
  end
end
