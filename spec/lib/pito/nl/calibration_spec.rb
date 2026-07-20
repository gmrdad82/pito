# frozen_string_literal: true

require "rails_helper"

# The NL mapper's EMPIRICAL THRESHOLDS GATE (3.0.0). Run this locally
# whenever spec/fixtures/nl_calibration.yml, the corpus in
# config/pito/tools.yml (`nl_examples:` on any tool), the embedding engine
# (embeddinggemma-300m via the sidecar), or tools.yml's own `nl.thresholds:`
# change — it is the thing that tells you whether 0.90 / 0.72 still hold, or
# need re-pinning against measured numbers rather than a guess.
#
# LIVE-GATED, ON PURPOSE: unlike router_spec.rb (which stubs
# Pito::Embedding::Client with deterministic vectors), this suite makes REAL
# HTTP calls through the router to the embedder sidecar so the numbers it
# reports are the ones the owner's actual embeddinggemma-300m model produces
# — a stubbed run would just re-assert whatever vectors we chose to fake.
# `calibration_available?` below skips the whole file cleanly (exit 0, no
# HTTP call at all) when ENV["PITO_EMBEDDER_URL"] is unset — which is every
# ordinary `bundle exec rspec` on CI or on a laptop without the sidecar up.
# To actually run it:
#
#   docker compose -f docker-compose.dev.yml up -d embedder
#   PITO_EMBEDDER_URL=http://127.0.0.1:8091 \
#     bundle exec rspec spec/lib/pito/nl/calibration_spec.rb
#
# TOOL RESOLUTION: a fixture `run:` string (e.g. "ls vids") names a tools.yml
# tool by its chat-shape leading token, which may be the canonical tool name
# OR a top-level alias ("ls" -> `list`, "glance" -> `at-a-glance`). This spec
# resolves that token through Pito::Grammar::Registry.specs_for_alias(
# namespace: :chat, token:) — the SAME alias index Pito::Chat::Parser queries
# for real input — rather than re-deriving alias membership from tools.yml
# by hand, so "what the fixture expects" can never drift from "what the
# grammar actually accepts".
RSpec.describe "Pito::Nl::Router calibration (empirical thresholds gate)" do
  # Uniquely named: RSpec.describe blocks don't scope constants, so a bare
  # FIXTURE_PATH here lands on Object and collides with the mapper gate's
  # when both files load in one process (the router gate then reads the
  # WRONG fixture and KeyErrors).
  ROUTER_FIXTURE_PATH = Rails.root.join("spec/fixtures/nl_calibration.yml")

  # ── Availability guard ───────────────────────────────────────────────────
  #
  # Two cheap checks, short-circuited in order: is the sidecar even
  # configured, then is it actually answering. Both are near-instant (no
  # embedding call, just a GET /health — the same endpoint the docker
  # healthcheck in docker-compose.dev.yml polls) so an ordinary CI/local run
  # without PITO_EMBEDDER_URL set never touches the network at all.
  def calibration_available?
    base_url = ENV["PITO_EMBEDDER_URL"]
    return false if base_url.blank?

    uri      = URI.parse("#{base_url.chomp('/')}/health")
    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 1, read_timeout: 1) { |http| http.get(uri.request_uri) }
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  # Resolves a fixture `run:` command's leading token (canonical tool name OR
  # alias) to the canonical tool Symbol Pito::Nl::Router itself reports (see
  # Router#corpus — its `tool:` is always a tools.yml top-level key). Raises
  # on an unresolvable token rather than silently comparing nil == nil: a
  # typo in the fixture should surface as a loud bug, not a false pass.
  def resolve_tool(run)
    leading = run.to_s.split(" ").first
    spec    = Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: leading)
    raise "nl_calibration.yml bug: run #{run.inspect} has no resolvable chat tool for leading token #{leading.inspect}" if spec.nil?

    spec.name
  end

  def route_row(entry)
    { say: entry[:say], run: entry[:run], expected_tool: resolve_tool(entry[:run]), result: Pito::Nl::Router.route(entry[:say]) }
  end

  def print_confidence_range(label, rows)
    confidences = rows.filter_map { |row| row[:result]&.fetch(:confidence) }
    if confidences.empty?
      puts "  #{label}: 0/#{rows.size} routed"
    else
      puts "  #{label}: #{confidences.size}/#{rows.size} routed, confidence #{confidences.min.round(3)}..#{confidences.max.round(3)}"
    end
  end

  before(:all) do
    skip "PITO_EMBEDDER_URL not reachable — start the embedder sidecar " \
         "(docker compose -f docker-compose.dev.yml up -d embedder) to run the NL calibration gate" unless calibration_available?

    # Registry isn't populated yet at this point — rails_helper's global
    # `before(:each)` (config/rails_helper.rb) only fires per-example, and
    # this hook runs once, before the first one.
    Pito::Grammar::Registry.register_all!
    Pito::Nl::Router.sync!
    # NOTE: before(:all)/before(:context) runs OUTSIDE the per-example
    # transactional-fixture rollback, so this sync! really commits rows to
    # nl_examples — the same idempotent digest-keyed upsert/prune
    # production boot performs, materializing the CURRENT tools.yml
    # corpus, never anything fixture-specific. NOT harmless to leave
    # behind, though: see the after(:all) cleanup below.

    fixture = YAML.safe_load_file(ROUTER_FIXTURE_PATH, symbolize_names: true)
    @auto_run_rows          = fixture.fetch(:auto_run).map { |e| route_row(e) }
    @suggest_rows           = fixture.fetch(:suggest).map  { |e| route_row(e) }
    @reject_rows            = fixture.fetch(:reject).map   { |e| { say: e[:say], result: Pito::Nl::Router.route(e[:say]) } }
    @tolerated_suggest_rows = fixture.fetch(:tolerated_suggest).map { |e| { say: e[:say], result: Pito::Nl::Router.route(e[:say]) } }

    thresholds          = Pito::Dispatch::Config.nl_thresholds
    @auto_run_threshold = thresholds.fetch(:auto_run)
    @suggest_threshold  = thresholds.fetch(:suggest)
  end

  # The sync! above commits OUTSIDE the per-example rollback; without this
  # the corpus rows leak into the shared pito_test DB and fail the
  # count-asserting specs of any later run in the same DB (router_spec's
  # empty-cache self-heal, /config embeddings' embedded/total counts).
  # Idempotent and skip-safe: on a skipped run the table is untouched
  # either way.
  after(:all) do
    Pito::Nl::Router::Example.delete_all
  end

  it "auto_run tier: routes every entry to its exact expected tool" do
    print_confidence_range("auto_run", @auto_run_rows)

    aggregate_failures do
      @auto_run_rows.each do |row|
        expect(row[:result]).not_to be_nil,
          "#{row[:say].inspect} -> nil (expected #{row[:expected_tool].inspect} via run #{row[:run].inspect})"
        next if row[:result].nil?

        expect(row[:result][:tool]).to eq(row[:expected_tool]),
          "#{row[:say].inspect} -> #{row[:result][:tool].inspect} at #{row[:result][:confidence].round(3)} " \
          "(expected #{row[:expected_tool].inspect} via run #{row[:run].inspect})"
      end
    end
  end

  it "suggest tier: routes every entry (tool match reported, not asserted — every phrase names a write tool the gate always confirms)" do
    print_confidence_range("suggest", @suggest_rows)

    mismatches = @suggest_rows.reject { |row| row[:result].nil? || row[:result][:tool] == row[:expected_tool] }
    if mismatches.any?
      puts "  suggest tool mismatches (informational only — a write-tool phrase always gets a " \
           "did-you-mean confirmation, correct tool or not; the gate never auto-runs it either way):"
      mismatches.each { |row| puts "    #{row[:say].inspect} -> #{row[:result][:tool]} (expected #{row[:expected_tool]})" }
    end

    aggregate_failures do
      @suggest_rows.each do |row|
        expect(row[:result]).not_to be_nil,
          "#{row[:say].inspect} -> nil (expected #{row[:expected_tool].inspect} via run #{row[:run].inspect}) " \
          "— no did-you-mean suggestion would be offered at all"
      end
    end
  end

  it "reject tier: never reaches the auto_run threshold (did-you-mean noise in [suggest, auto_run) is acceptable)" do
    noise = @reject_rows.select do |row|
      row[:result] && row[:result][:confidence] >= @suggest_threshold && row[:result][:confidence] < @auto_run_threshold
    end
    if noise.any?
      puts "  reject tier did-you-mean noise (below auto_run — acceptable, listed not failed):"
      noise.each { |row| puts "    #{row[:say].inspect} -> #{row[:result][:tool]} at #{row[:result][:confidence].round(3)}" }
    end

    aggregate_failures do
      @reject_rows.each do |row|
        next if row[:result].nil?

        expect(row[:result][:confidence]).to be < @auto_run_threshold,
          "#{row[:say].inspect} reached #{row[:result][:confidence].round(3)} confidence as #{row[:result][:tool]} " \
          "— at/above auto_run (#{@auto_run_threshold}); a reject phrase must NEVER auto-dispatch"
      end
    end
  end

  it "tolerated_suggest tier: never auto-runs (a did-you-mean, or no match at all, is acceptable either way)" do
    print_confidence_range("tolerated_suggest", @tolerated_suggest_rows)

    aggregate_failures do
      @tolerated_suggest_rows.each do |row|
        next if row[:result].nil?

        expect(row[:result][:confidence]).to be < @auto_run_threshold,
          "#{row[:say].inspect} reached #{row[:result][:confidence].round(3)} confidence as #{row[:result][:tool]} " \
          "— at/above auto_run (#{@auto_run_threshold}); a domain-adjacent phrase must NEVER auto-dispatch, " \
          "only ever at most a confirm-first did-you-mean"
      end
    end
  end
end
