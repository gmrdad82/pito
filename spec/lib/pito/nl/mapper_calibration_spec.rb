# frozen_string_literal: true

require "rails_helper"

# The NL MAPPER's EMPIRICAL COMPOSITION GATE (3.0.1). Run this locally
# whenever spec/fixtures/nl_mapper_calibration.yml, `nl.exemplars:` /
# `nl.thresholds:` / any tool's grammar-relevant fields in
# config/pito/tools.yml, or the qwen nlmapper sidecar's model/quant change —
# it is the thing that tells you whether Pito::Nl::Mapper (see lib/pito/nl/
# mapper.rb) still COMPOSES a correct command, not just a parseable one.
#
# This is a DIFFERENT stage from spec/lib/pito/nl/calibration_spec.rb (that
# suite judges Pito::Nl::Router's cosine-similarity thresholds against the
# EMBEDDER sidecar) — see ~/Dev/dev-notes/pito/nl-artifacts-guide.md §1 for
# the two-stage router-vs-mapper model. spec/lib/pito/nl/mapper_spec.rb is a
# THIRD file again: a fully-stubbed unit spec of Mapper's internals
# (CompletionClient never hit) — this file is the live-gated sibling.
#
# LIVE-GATED, ON PURPOSE: this suite makes REAL HTTP calls through
# Pito::Nl::Mapper to the nlmapper sidecar (llama.cpp serving
# Qwen3-0.6B-GGUF under a GBNF grammar) so the compositions it grades are the
# ones the owner's actual sidecar produces — a stubbed run would just
# re-assert whatever completion we chose to fake. Since the v2
# retrieval-picked few-shot (see mapper.rb's #chat_messages design note) the
# EMBEDDER sidecar is required too: without it the mapper degrades to its
# static full-pool fallback prompt, whose compositions are NOT what this
# fixture's expectations were calibrated against — so the availability guard
# below skips the live example cleanly (no completion call) unless BOTH
# ENV["PITO_NLMAPPER_URL"] and ENV["PITO_EMBEDDER_URL"] are set and answering
# /health — which is every ordinary `bundle exec rspec` on CI or on a laptop
# without the sidecars up. The GBNF-grammar-builds example has NO such guard:
# it never touches the network and always runs.
#
# To actually run the live example:
#
#   docker compose -f docker-compose.dev.yml up -d embedder nlmapper
#   PITO_EMBEDDER_URL=http://127.0.0.1:8091 \
#   PITO_NLMAPPER_URL=http://127.0.0.1:8092 \
#     bundle exec rspec spec/lib/pito/nl/mapper_calibration_spec.rb
#
# A NOTE ON DETERMINISM: unlike the router (a cosine lookup), the mapper
# samples from an LLM. Empirically (2026-07-16, two back-to-back live runs)
# it composed byte-identical output for every fixture entry both times —
# treat a fixture entry that flakes as a genuine signal, not noise, but a
# single re-run is cheap insurance against a one-off sidecar hiccup (a
# parallel task may be growing `nl.exemplars:` mid-run, which changes the
# mapper's few-shot prompt on the very next call — see mapper.rb's #grammar
# memoization comment).
RSpec.describe "Pito::Nl::Mapper calibration (empirical composition gate)" do
  FIXTURE_PATH = Rails.root.join("spec/fixtures/nl_mapper_calibration.yml")

  # ── Availability guard ───────────────────────────────────────────────────
  #
  # Mirrors calibration_spec.rb's own guard exactly, generalized over the env
  # var: is the sidecar URL even configured, then is it actually answering
  # /health (the same endpoint the docker healthchecks in
  # docker-compose.dev.yml poll for the `nlmapper`/`embedder` services).
  # Near-instant (no completion/embed call), so an ordinary run without the
  # env vars never touches the network. BOTH sidecars are required since the
  # v2 retrieval-picked few-shot — see the header comment for why an
  # embedder-less run would grade the wrong (fallback) prompt.
  def sidecar_available?(env_var)
    base_url = ENV[env_var]
    return false if base_url.blank?

    uri      = URI.parse("#{base_url.chomp('/')}/health")
    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 1, read_timeout: 1) { |http| http.get(uri.request_uri) }
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def mapper_available?
    sidecar_available?("PITO_NLMAPPER_URL") && sidecar_available?("PITO_EMBEDDER_URL")
  end

  # Independently re-proves the composed +command+ re-parses to a REAL chat
  # tool through the SAME pipeline Pito::Nl::Mapper#parsed_tool runs
  # internally (Pito::Lex::Lexer -> Pito::Lex::KeywordSanitizer ->
  # Pito::Chat::Parser) — belt-and-suspenders on top of Mapper.map's own
  # internal validation (a non-nil result already implies this), so a future
  # regression in that internal check would still be caught here rather than
  # silently trusted. Returns the parsed tool Symbol, or nil when the command
  # doesn't parse to a fresh (:new_turn) chat command.
  def reparsed_tool(command)
    tokens  = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(command))
    message = Pito::Chat::Parser.call(tokens, raw: command, conversation: nil)
    return nil unless message.kind == :new_turn

    message.tool
  rescue Pito::Chat::Parser::NotAChatMessage
    nil
  end

  it "builds the GBNF grammar for the current tools.yml without raising" do
    expect { Pito::Nl::GbnfBuilder.call }.not_to raise_error
  end

  it "composes a command at the expected tool for every held-out entries: phrasing" do
    skip "PITO_NLMAPPER_URL/PITO_EMBEDDER_URL not reachable — start both sidecars " \
         "(docker compose -f docker-compose.dev.yml up -d embedder nlmapper) to run the NL mapper calibration gate" unless mapper_available?

    fixture = YAML.safe_load_file(FIXTURE_PATH, symbolize_names: true)
    rows = fixture.fetch(:entries).map do |entry|
      { say: entry[:say], expected_tool: entry[:tool].to_sym, result: Pito::Nl::Mapper.map(entry[:say]) }
    end

    rows.each do |row|
      next if row[:result].nil?

      puts "  #{row[:say].inspect} -> #{row[:result][:command].inspect} (tool #{row[:result][:tool].inspect})"
    end

    aggregate_failures do
      rows.each do |row|
        expect(row[:result]).not_to be_nil,
          "#{row[:say].inspect} -> nil (expected #{row[:expected_tool].inspect}) — the mapper produced no valid completion"
        next if row[:result].nil?

        expect(reparsed_tool(row[:result][:command])).not_to be_nil,
          "#{row[:say].inspect} -> #{row[:result][:command].inspect} does not re-parse to a fresh (:new_turn) chat command"

        expect(row[:result][:tool]).to eq(row[:expected_tool]),
          "#{row[:say].inspect} -> #{row[:result][:command].inspect} composed tool #{row[:result][:tool].inspect}, " \
          "expected #{row[:expected_tool].inspect}"
      end
    end
  end
end
