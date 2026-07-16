# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:embeddings:reindex", type: :rake do
  before(:all) { load_tasks } # rubocop:disable RSpec/BeforeAfterAll

  before do
    reenable("pito:embeddings:reindex")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return("http://embedder.test")
    allow(ENV).to receive(:[]).with("FORCE").and_return(nil)
    allow(ENV).to receive(:[]).with("THROTTLE").and_return(nil)
  end

  def invoke_task
    Rake::Task["pito:embeddings:reindex"].invoke
  end

  # Swaps $stdout for a StringIO for the duration of the block and returns
  # everything written to it — used where a test needs to assert on the
  # printed summary lines, not just on the indexer calls.
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  context "when PITO_EMBEDDER_URL is blank" do
    before do
      allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return(nil)
    end

    it "aborts before touching any indexer" do
      create(:game)
      create(:video)
      create(:event, kind: "echo")

      expect(Game::EmbeddingIndexer).not_to receive(:call)
      expect(Video::EmbeddingIndexer).not_to receive(:call)
      expect(Pito::Embedding::EventIndexer).not_to receive(:call)

      expect { suppress_output { invoke_task } }.to raise_error(SystemExit)
    end
  end

  context "sweeping all three collections" do
    let!(:games) { create_list(:game, 2) }
    let!(:videos) { create_list(:video, 2) }
    let!(:echo_event) { create(:event, kind: "echo") }
    let!(:enhanced_event) { create(:event, kind: "enhanced") }
    let!(:confirmation_event) { create(:event, kind: "confirmation") }
    let!(:thinking_event) { create(:event, kind: "thinking") }

    before do
      allow(Game::EmbeddingIndexer).to receive(:call)
      allow(Video::EmbeddingIndexer).to receive(:call)
      allow(Pito::Embedding::EventIndexer).to receive(:call)
    end

    it "reaches every eligible record exactly once and never passes a non-allowlisted event kind" do
      suppress_output { invoke_task }

      games.each do |game|
        expect(Game::EmbeddingIndexer).to have_received(:call).with(game, force: false).once
      end
      videos.each do |video|
        expect(Video::EmbeddingIndexer).to have_received(:call).with(video, force: false).once
      end
      expect(Pito::Embedding::EventIndexer).to have_received(:call).with(echo_event, force: false).once
      expect(Pito::Embedding::EventIndexer).to have_received(:call).with(enhanced_event, force: false).once
      expect(Pito::Embedding::EventIndexer).not_to have_received(:call).with(confirmation_event, any_args)
      expect(Pito::Embedding::EventIndexer).not_to have_received(:call).with(thinking_event, any_args)
    end
  end

  context "when a per-row EmbeddingNil interrupts the games sweep" do
    let!(:failing_game) { create(:game) }
    let!(:next_game) { create(:game) }

    before do
      allow(Video::EmbeddingIndexer).to receive(:call)
      allow(Pito::Embedding::EventIndexer).to receive(:call)
      allow(Game::EmbeddingIndexer).to receive(:call) do |record, **|
        if record == failing_game
          raise Pito::Error::EmbeddingNil.new(resource_type: "game", resource_id: record.id)
        end
      end
    end

    it "continues to the next game and counts the failure in the summary" do
      output = capture_stdout { invoke_task }

      expect(Game::EmbeddingIndexer).to have_received(:call).with(failing_game, force: false)
      expect(Game::EmbeddingIndexer).to have_received(:call).with(next_game, force: false)
      expect(output).to match(/games ##{failing_game.id} FAILED/)
      expect(output).to match(/games: 0 embedded, 1 skipped, 1 failed \(2 total\)/)
    end
  end

  context "FORCE=1" do
    before do
      allow(ENV).to receive(:[]).with("FORCE").and_return("1")
      allow(Game::EmbeddingIndexer).to receive(:call)
      allow(Video::EmbeddingIndexer).to receive(:call)
      allow(Pito::Embedding::EventIndexer).to receive(:call)
    end

    it "passes force: true through to every indexer" do
      game = create(:game)
      video = create(:video)
      event = create(:event, kind: "echo")

      suppress_output { invoke_task }

      expect(Game::EmbeddingIndexer).to have_received(:call).with(game, force: true)
      expect(Video::EmbeddingIndexer).to have_received(:call).with(video, force: true)
      expect(Pito::Embedding::EventIndexer).to have_received(:call).with(event, force: true)
    end
  end

  context "output" do
    before do
      allow(Game::EmbeddingIndexer).to receive(:call)
      allow(Video::EmbeddingIndexer).to receive(:call)
      allow(Pito::Embedding::EventIndexer).to receive(:call)
    end

    it "prints a per-collection summary line plus the overall total" do
      create(:game)
      create(:video)
      create(:event, kind: "echo")

      output = capture_stdout { invoke_task }

      expect(output).to match(/games: 0 embedded, 1 skipped, 0 failed \(1 total\)/)
      expect(output).to match(/videos: 0 embedded, 1 skipped, 0 failed \(1 total\)/)
      expect(output).to match(/events: 0 embedded, 1 skipped, 0 failed \(1 total\)/)
      expect(output).to match(/Done\. 0 embedded, 3 skipped, 0 failed overall\./)
    end
  end
end
