# frozen_string_literal: true

require "rails_helper"

# Drift insurance for the top-level `nl.exemplars:` corpus (config/pito/
# tools.yml) — the GBNF mapper's few-shot say/run worked examples (see
# Pito::Nl::Mapper#build_prompt). Pito::Dispatch::Schema already proves the
# SHAPE of every entry is legal (say/run both present, non-blank Strings —
# spec/dispatch/schema_spec.rb); this suite proves something schema
# validation can't: that each entry's `run:` string is still a REAL,
# grammar-recognized chat command TODAY. Without it, a tools.yml edit that
# renames/removes a tool or alias could leave an exemplar's `run:` silently
# unparseable — the mapper would keep few-shotting a command the grammar no
# longer accepts, and nothing would fail until an owner noticed the mapper
# routing worse (3.0.1 P11).
RSpec.describe "nl.exemplars run strings stay parseable", type: :dispatch do
  it "parses every nl.exemplars run: string to kind :new_turn" do
    exemplars = Pito::Dispatch::Config.nl_exemplars
    expect(exemplars).not_to be_empty # a suite that silently checks nothing is worse than none

    aggregate_failures do
      exemplars.each do |exemplar|
        run = exemplar.fetch(:run)
        message = Pito::Chat::Parser.call(
          Pito::Lex::Lexer.call(run), raw: run, conversation: Conversation.singleton
        )

        expect(message.kind).to eq(:new_turn),
          "nl.exemplars run #{run.inspect} (say: #{exemplar[:say].inspect}) parsed to " \
          "kind #{message.kind.inspect}, not :new_turn — the grammar no longer recognizes it"
      end
    end
  end
end
