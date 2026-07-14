# frozen_string_literal: true

require "rails_helper"

# ── Pito::Achievements::Config — the config/pito/shinies.yml loader ─────────
#
# Mirrors Pito::Dispatch::Config (lib/pito/dispatch/config.rb, tools.yml) in
# both implementation and test style — see spec/lib/pito/fx/registry_spec.rb
# for the sibling Pito::Fx::Registry loader, which this spec's fixture-file
# technique (stub_const on PATH + reload!) is cribbed from.
#
# LEAK-PROOFING: an around hook reloads the REAL config both before and after
# every example. Reloading only in an `after` hook would run before
# rspec-mocks reverts stub_const (mocks teardown happens INSIDE example.run,
# after the example's own after-hooks) and could still see the stubbed PATH;
# wrapping with `around` guarantees the post-example reload! runs once
# example.run has fully returned, i.e. after stub_const has already reverted
# PATH to the real file — so no fixture ever leaks into a later spec.
RSpec.describe Pito::Achievements::Config do
  around do |example|
    described_class.reload!
    example.run
  ensure
    described_class.reload!
  end

  # A minimal, valid shinies document — every mutation test below `.sub`s a
  # unique fragment out of this string. Every ceiling/award number is
  # distinct across the whole document so each substitution target is
  # unambiguous.
  VALID_SHINIES = <<~YML
    schema_version: 1
    ceilings:
      video:
        subs_gained: 101
        views: 202
      game:
        subs_gained: 303
        views: 404
      channel:
        subs: 505
        views: 606
    awards:
      silver: 1000
      gold: 2000
      diamond: 3000
  YML

  # Write +yaml+ to a temp file, point the loader at it, and yield.
  def with_shinies(yaml)
    Tempfile.create([ "shinies", ".yml" ]) do |f|
      f.write(yaml)
      f.flush
      stub_const("Pito::Achievements::Config::PATH", Pathname.new(f.path))
      described_class.reload!
      yield
    end
  end

  # ── Defaults: the real shipped config/pito/shinies.yml ─────────────────────
  describe "the shipped config/pito/shinies.yml" do
    describe ".ceilings" do
      it "returns the video scope's ceilings (subs_gained, not subs)" do
        expect(described_class.ceilings["Video"]).to eq(
          "subs_gained" => 5_000, "views" => 1_000_000, "watched_hours" => 100_000,
          "likes" => 20_000, "comments" => 5_000
        )
      end

      it "returns the game scope's ceilings (subs_gained, not subs)" do
        expect(described_class.ceilings["Game"]).to eq(
          "subs_gained" => 10_000, "views" => 10_000_000, "watched_hours" => 500_000,
          "likes" => 200_000, "comments" => 20_000
        )
      end

      it "returns the channel scope's ceilings (subs, not subs_gained)" do
        expect(described_class.ceilings["Channel"]).to eq(
          "subs" => 50_000, "views" => 50_000_000, "watched_hours" => 2_000_000,
          "likes" => 500_000, "comments" => 50_000
        )
      end
    end

    it ".awards returns the metal ladder ascending by threshold" do
      expect(described_class.awards).to eq(100_000 => "silver", 1_000_000 => "gold", 10_000_000 => "diamond")
    end

    describe ".metrics_for" do
      it "returns Channel metrics in file order, subs first" do
        expect(described_class.metrics_for("Channel")).to eq(%w[subs views watched_hours likes comments])
      end

      it "returns Video metrics starting with subs_gained" do
        expect(described_class.metrics_for("Video").first).to eq("subs_gained")
      end

      it "returns [] for an unknown scope" do
        expect(described_class.metrics_for("Playlist")).to eq([])
      end
    end
  end

  # ── LoadError branches ───────────────────────────────────────────────────────
  describe "LoadError branches" do
    it "raises when the file does not exist" do
      Dir.mktmpdir do |dir|
        missing_path = Pathname.new(dir).join("does_not_exist.yml")
        stub_const("Pito::Achievements::Config::PATH", missing_path)
        described_class.reload!

        expect { described_class.ceilings }.to raise_error(LoadError, /#{Regexp.escape(missing_path.to_s)} not found/)
      end
    end

    it "raises on an unsupported schema_version" do
      with_shinies(VALID_SHINIES.sub("schema_version: 1", "schema_version: 999")) do
        expect { described_class.ceilings }.to raise_error(LoadError, /unsupported schema_version 999/)
      end
    end

    it "raises on an unknown ceiling scope key" do
      with_shinies(VALID_SHINIES.sub("awards:", "  playlist:\n    subs_gained: 1\nawards:")) do
        expect { described_class.ceilings }.to raise_error(LoadError, /unknown ceiling scope\(s\).*playlist/)
      end
    end

    it "raises on a missing ceiling scope" do
      with_shinies(VALID_SHINIES.sub("  game:\n    subs_gained: 303\n    views: 404\n", "")) do
        expect { described_class.ceilings }.to raise_error(LoadError, /missing ceiling scope\(s\).*game/)
      end
    end

    it "raises on an unknown metric" do
      with_shinies(VALID_SHINIES.sub("views: 202", "viewz: 202")) do
        expect { described_class.ceilings }.to raise_error(LoadError, /unknown metric "viewz" under ceilings\.video/)
      end
    end

    it "raises on a zero ceiling" do
      with_shinies(VALID_SHINIES.sub("views: 202", "views: 0")) do
        expect { described_class.ceilings }.to raise_error(
          LoadError, /ceilings\.video\.views must be a positive integer \(got 0\)/
        )
      end
    end

    it "raises on a negative ceiling" do
      with_shinies(VALID_SHINIES.sub("views: 202", "views: -5")) do
        expect { described_class.ceilings }.to raise_error(
          LoadError, /ceilings\.video\.views must be a positive integer \(got -5\)/
        )
      end
    end

    it "raises on a string ceiling" do
      with_shinies(VALID_SHINIES.sub("views: 202", "views: not_a_number")) do
        expect { described_class.ceilings }.to raise_error(
          LoadError, /ceilings\.video\.views must be a positive integer \(got "not_a_number"\)/
        )
      end
    end

    it "raises when award thresholds do not strictly ascend" do
      with_shinies(VALID_SHINIES.sub("silver: 1000\n  gold: 2000", "silver: 2000\n  gold: 1000")) do
        expect { described_class.awards }.to raise_error(LoadError, /award thresholds must strictly ascend/)
      end
    end

    it "raises on a non-integer award threshold" do
      with_shinies(VALID_SHINIES.sub("silver: 1000", "silver: 1000.5")) do
        expect { described_class.awards }.to raise_error(LoadError, /award thresholds must be positive integers/)
      end
    end
  end

  # ── reload! ───────────────────────────────────────────────────────────────
  describe ".reload!" do
    it "memoizes until reload!, then re-reads the file" do
      Tempfile.create([ "shinies", ".yml" ]) do |f|
        f.write(VALID_SHINIES)
        f.flush
        stub_const("Pito::Achievements::Config::PATH", Pathname.new(f.path))
        described_class.reload!
        expect(described_class.metrics_for("Video")).to eq(%w[subs_gained views])

        f.rewind
        f.truncate(0)
        f.write(VALID_SHINIES.sub("views: 202", "watched_hours: 202"))
        f.flush
        expect(described_class.metrics_for("Video")).to eq(%w[subs_gained views]) # still memoized

        described_class.reload!
        expect(described_class.metrics_for("Video")).to eq(%w[subs_gained watched_hours]) # re-read
      end
    end
  end
end
