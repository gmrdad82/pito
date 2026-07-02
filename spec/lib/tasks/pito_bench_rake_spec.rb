# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:bench" do
  describe Pito::Bench::Runner do
    let(:conversation) { create(:conversation) }
    let(:turn)         { create(:turn, conversation:) }
    let(:root)         { Pathname.new(Dir.mktmpdir) }
    let(:io)           { StringIO.new }

    before do
      create(:event, conversation:, turn:, kind: "echo",   payload: { "text" => "list vids" }, position: 1)
      create(:event, conversation:, turn:, kind: "system", payload: { "body" => "hello" },     position: 2)
    end

    after { FileUtils.remove_entry(root) }

    def run
      described_class.call(uuid: conversation.uuid, iterations: 1, io:, root:)
    end

    it "runs every registered step without a fatal error" do
      results = run[:steps]

      expect(results.map { |r| r["step"] })
        .to eq(Pito::Bench::Runner::STEPS.map(&:label))
      expect(results.map { |r| r["error"] }).to all(be_nil)
    end

    it "times the replay of the given conversation" do
      replay = run[:steps].find { |r| r["step"] == "replay" }

      expect(replay["metrics"]["uuid"]).to eq(conversation.uuid)
      expect(replay["metrics"]["events"]).to eq(2)
      expect(replay["metrics"]["total_ms"]).to be > 0
    end

    it "writes a parseable JSON snapshot under root tmp/bench" do
      snapshot = run[:snapshot]

      expect(snapshot.to_s).to start_with(root.join("tmp/bench").to_s)
      parsed = JSON.parse(snapshot.read)
      expect(parsed["steps"].length).to eq(Pito::Bench::Runner::STEPS.length)
      expect(parsed["iterations"]).to eq(1)
    end

    it "deactivates the network guard and re-opens the DB session afterwards" do
      run

      expect(Pito::Bench::NetworkGuard.active?).to be(false)
      # A write AFTER the run must succeed — the read-only session was reset.
      expect { create(:notification) }.not_to raise_error
    end

    it "blocks any outbound HTTP attempt during a step" do
      probe = Module.new do
        def self.label = "http-probe"

        def self.call(_ctx)
          Net::HTTP.get(URI("http://example.com/"))
        end
      end

      result = described_class.call(uuid: conversation.uuid, iterations: 1, io:, root:, steps: [ probe ])

      expect(result[:steps].first["error"]).to match(/NetworkGuard::BlockedError/)
    end
  end

  # NON-transactional: `SET default_transaction_read_only` applies to FUTURE
  # transactions, so under transactional fixtures (one wrapping transaction) it
  # never bites. Autocommit — as in a real rake run — is where the guard lives.
  # The probe itself is the only would-be write and it must FAIL, so nothing
  # needs cleanup.
  describe "read-only session (non-transactional)" do
    self.use_transactional_tests = false

    let(:root) { Pathname.new(Dir.mktmpdir) }

    after { FileUtils.remove_entry(root) }

    it "surfaces a write attempt during a step as a read-only violation" do
      probe = Module.new do
        def self.label = "write-probe"

        def self.call(_ctx)
          # Raw SQL so no model validation can intercept before the DB —
          # this must hit PG's read-only session guard itself.
          ActiveRecord::Base.connection.execute(
            "INSERT INTO api_requests (provider, created_at) VALUES ('bench-probe', NOW())"
          )
        end
      end

      result = Pito::Bench::Runner.call(iterations: 1, io: StringIO.new, root:, steps: [ probe ])

      expect(result[:steps].first["error"]).to match(/ReadOnly/i)
      expect(ApiRequest.where(provider: "bench-probe")).to be_empty
    end
  end

  describe "rake wiring", type: :rake do
    before(:all) { load_tasks } # rubocop:disable RSpec/BeforeAfterAll

    before { reenable("pito:bench") }

    it "delegates to the Runner with UUID/N from the environment" do
      allow(Pito::Bench::Runner).to receive(:call)
      ENV["UUID"] = "abc-123"
      ENV["N"]    = "7"

      Rake::Task["pito:bench"].invoke

      expect(Pito::Bench::Runner).to have_received(:call).with(uuid: "abc-123", iterations: 7)
    ensure
      ENV.delete("UUID")
      ENV.delete("N")
    end
  end
end
