# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:traits rake tasks", type: :rake do
  before(:all) { load_tasks } # rubocop:disable RSpec/BeforeAfterAll

  before do
    reenable("pito:traits:derive")
    reenable("pito:traits:export")
    reenable("pito:traits:import")
  end

  # Swaps $stdout for a StringIO for the duration of the block and returns
  # everything written to it (mirrors spec/lib/tasks/pito_embeddings_spec.rb).
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def stub_traits_file(path)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TRAITS_FILE").and_return(path)
  end

  let(:tmp_dir) { Dir.mktmpdir }

  def tmp_path(name = "traits_classify.yml")
    File.join(tmp_dir, name)
  end

  # ── pito:traits:derive ────────────────────────────────────────────────

  describe "pito:traits:derive" do
    it "derives tags from synced IGDB data and prints changed/unchanged/error counts" do
      create(:game, themes: [ "Action" ])
      create(:game) # nothing to derive — stays unchanged

      output = capture_stdout { Rake::Task["pito:traits:derive"].invoke }

      expect(output).to match(/Derive: 1 changed, 1 unchanged, 0 errors \(2 total\)/)
    end

    it "is idempotent — a second run changes nothing" do
      create(:game, themes: [ "Action" ])
      suppress_output { Rake::Task["pito:traits:derive"].invoke }
      reenable("pito:traits:derive")

      output = capture_stdout { Rake::Task["pito:traits:derive"].invoke }
      expect(output).to match(/Derive: 0 changed, 1 unchanged, 0 errors/)
    end
  end

  # ── pito:traits:export ────────────────────────────────────────────────

  describe "pito:traits:export" do
    it "writes every game, ordered by id, to TRAITS_FILE and prints the count" do
      path = tmp_path
      stub_traits_file(path)
      g1 = create(:game, title: "Alpha")
      g2 = create(:game, :with_traits, title: "Beta")

      output = capture_stdout { Rake::Task["pito:traits:export"].invoke }

      expect(output).to include("Exported 2 games to #{path}")
      data = YAML.safe_load_file(path, aliases: false)
      expect(data["games"].map { |g| g["id"] }).to eq([ g1.id, g2.id ])
    end

    it "prefills classified/owner scale values and skips derived tags, marks unsynced games" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game, :with_traits, igdb_synced_at: nil) # :with_traits sets difficulty/story + action (derived)

      Rake::Task["pito:traits:export"].invoke
      data = YAML.safe_load_file(path, aliases: false)
      entry = data["games"].first

      expect(entry["difficulty"]).to eq("brutal")
      expect(entry["tags"]).to include("skill_based", "worth_it")
      expect(entry["tags"]).not_to include("action") # derived — never in the export
      expect(entry["overrides"]).to eq({})
      expect(File.read(path)).to include("# igdb — not synced")
    end

    it "leaves an unset scale blank (nil once parsed)" do
      path = tmp_path
      stub_traits_file(path)
      create(:game)

      Rake::Task["pito:traits:export"].invoke
      entry = YAML.safe_load_file(path, aliases: false)["games"].first
      expect(entry["pace"]).to be_nil
    end
  end

  # ── pito:traits:import ────────────────────────────────────────────────

  describe "pito:traits:import" do
    it "aborts when TRAITS_FILE does not exist" do
      stub_traits_file(tmp_path("missing.yml"))
      expect { suppress_output { Rake::Task["pito:traits:import"].invoke } }.to raise_error(SystemExit)
    end

    it "validates the whole file first and writes NOTHING when any row is invalid" do
      path = tmp_path
      stub_traits_file(path)
      good = create(:game)
      File.write(path, { "games" => [
        { "id" => good.id, "difficulty" => "brutal", "tags" => [], "overrides" => {} },
        { "id" => good.id + 999_999, "tags" => [], "overrides" => {} } # unknown id
      ] }.to_yaml)

      expect { suppress_output { Rake::Task["pito:traits:import"].invoke } }.to raise_error(SystemExit)
      expect(good.reload.traits).to eq({})
    end

    it "rejects an out-of-vocabulary scale value" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      File.write(path, { "games" => [ { "id" => game.id, "difficulty" => "impossible" } ] }.to_yaml)

      expect { suppress_output { Rake::Task["pito:traits:import"].invoke } }.to raise_error(SystemExit)
      expect(game.reload.traits).to eq({})
    end

    it "rejects a derived tag name at the top level" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      File.write(path, { "games" => [ { "id" => game.id, "tags" => [ "action" ] } ] }.to_yaml)

      expect { suppress_output { Rake::Task["pito:traits:import"].invoke } }.to raise_error(SystemExit)
      expect(game.reload.traits).to eq({})
    end

    it "applies classified scales/tags and enqueues a re-embed" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      File.write(path, { "games" => [
        { "id" => game.id, "difficulty" => "brutal", "tags" => %w[space skill_based], "overrides" => {} }
      ] }.to_yaml)

      expect { suppress_output { Rake::Task["pito:traits:import"].invoke } }
        .to have_enqueued_job(GameEmbedIndexJob).with(game.id)

      game.reload
      expect(game.trait_value("difficulty")).to eq("brutal")
      expect(game.trait_source("difficulty")).to eq("classified")
      expect(game.trait_tags).to match_array(%w[space skill_based])
    end

    it "applies overrides with source owner, including a pinned-absent \"!tag\"" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      File.write(path, { "games" => [
        { "id" => game.id, "tags" => %w[space],
          "overrides" => { "difficulty" => "brutal", "tags" => %w[space !awful] } }
      ] }.to_yaml)

      suppress_output { Rake::Task["pito:traits:import"].invoke }
      game.reload

      expect(game.trait_source("difficulty")).to eq("owner")
      expect(game.trait_source("space")).to eq("owner")
      expect(game.trait_tags).not_to include("awful")
      expect(game.trait_source("awful")).to eq("owner") # pinned absent
    end

    it "NEVER overwrites an owner-sourced value and reports it as an owner keep" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      Game::Traits::Apply.call(game: game, source: "owner", scales: { "story" => "catching" })

      File.write(path, { "games" => [ { "id" => game.id, "story" => "bad", "tags" => [] } ] }.to_yaml)

      output = capture_stdout { Rake::Task["pito:traits:import"].invoke }

      expect(game.reload.trait_value("story")).to eq("catching")
      expect(output).to match(/Owner keeps:\s+1/)
    end

    it "prints a warning (not an error) on a title mismatch, and still applies the row" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game, title: "Real Title")
      File.write(path, { "games" => [
        { "id" => game.id, "title" => "Wrong Title", "difficulty" => "brutal", "tags" => [] }
      ] }.to_yaml)

      output = capture_stdout { Rake::Task["pito:traits:import"].invoke }

      expect(output).to include("WARNING")
      expect(output).to include("title mismatch")
      expect(game.reload.trait_value("difficulty")).to eq("brutal")
    end

    it "prints honest totals for a mixed-outcome import" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game)
      File.write(path, { "games" => [
        { "id" => game.id, "difficulty" => "brutal", "tags" => [ "space" ] }
      ] }.to_yaml)

      output = capture_stdout { Rake::Task["pito:traits:import"].invoke }

      expect(output).to match(/Games touched:\s+1/)
      expect(output).to match(/Values set:\s+2/) # difficulty + space
      expect(output).to include("Re-embeds for every touched game are enqueued")
    end

    it "round-trips cleanly: exporting then re-importing an untouched file changes nothing" do
      path = tmp_path
      stub_traits_file(path)
      game = create(:game, :with_traits)

      suppress_output { Rake::Task["pito:traits:export"].invoke }
      reenable("pito:traits:export")

      output = capture_stdout { Rake::Task["pito:traits:import"].invoke }
      expect(output).to match(/Games touched:\s+0/)
      expect(game.reload.trait_value("difficulty")).to eq("brutal")
    end
  end

  # ── pito:nightly ──────────────────────────────────────────────────────

  describe "pito:nightly" do
    before do
      # The chained sub-tasks may already be marked invoked (and thus a
      # silent no-op) by an earlier example anywhere in this run — reenable
      # every task this one composes, not just itself, or the chain would
      # silently skip a step depending on spec run order.
      reenable("pito:nightly")
      reenable("pito:traits:derive")
      reenable("pito:nl:sync")
      reenable("pito:embeddings:reindex")

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return("http://embedder.test")
      allow(Pito::Nl::Router).to receive(:sync!).and_return(upserted: 0, pruned: 0, embedded: 0)
      allow(Game::EmbeddingIndexer).to receive(:call)
      allow(Video::EmbeddingIndexer).to receive(:call)
      allow(Pito::Embedding::EventIndexer).to receive(:call)
    end

    it "is registered" do
      expect(Rake::Task.task_defined?("pito:nightly")).to be(true)
    end

    it "invokes traits:derive, nl:sync, and embeddings:reindex, in that order" do
      call_order = []
      allow(Rake::Task["pito:traits:derive"]).to receive(:invoke) { call_order << :derive }
      allow(Rake::Task["pito:nl:sync"]).to receive(:invoke) { call_order << :nl_sync }
      allow(Rake::Task["pito:embeddings:reindex"]).to receive(:invoke) { call_order << :embeddings_reindex }

      suppress_output { Rake::Task["pito:nightly"].invoke }

      expect(call_order).to eq(%i[derive nl_sync embeddings_reindex])
    end

    it "runs the full heal end to end: derives a game's trait, syncs the NL cache, reindexes embeddings" do
      game = create(:game, themes: [ "Action" ]) # has a pending derivable tag ("action")

      suppress_output { Rake::Task["pito:nightly"].invoke }

      expect(game.reload.trait_tags).to include("action")
      expect(Pito::Nl::Router).to have_received(:sync!)
      expect(Game::EmbeddingIndexer).to have_received(:call).with(game, force: false)
    end
  end
end
