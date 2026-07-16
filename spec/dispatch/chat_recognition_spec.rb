# frozen_string_literal: true

require "rails_helper"

# Phase D — chat verb recognition. For EVERY chat grammar verb (canonical + every
# alias), the dispatcher must resolve the same canonical verb, route to :chat, and
# (for verbs backed by a handler) map to that handler class. Pure: no DB, no exec.
RSpec.describe "Dispatch — chat verb recognition", type: :dispatch do
  CHAT_SPECS = Pito::Grammar::Registry.specs(namespace: :chat).freeze

  # Canonical verbs that MUST resolve to a handler class (the actionable chat
  # verbs). greet/farewell are NL-detected (phrase-matched, handler-less at
  # the grammar layer); `find` declares no chat: branch at all (3.0.1 P6) so
  # it never appears in CHAT_SPECS below — none of the three land here.
  # Asserted separately (find: spec/dispatch/chat/find_matrix_spec.rb).
  HANDLER_BACKED = %i[
    list show analyze sync link unlink delete reindex platform price footage
    publish unlist schedule shinies import help
  ].freeze

  describe "canonical + alias tokens resolve to the canonical verb" do
    CHAT_SPECS.each do |spec|
      ([ spec.name ] + Array(spec.aliases)).each do |token|
        it "#{token.inspect} → verb #{spec.name} (stack :chat)" do
          intent = parsed_intent("#{token} some args here")
          expect(intent[:stack]).to eq(:chat)
          expect(intent[:tool]).to eq(spec.name)
        end
      end
    end
  end

  describe "handler-backed verbs map to a handler class" do
    HANDLER_BACKED.each do |verb|
      it "#{verb} → a Pito::Chat::Handlers class, known: true" do
        intent = parsed_intent(verb.to_s)
        expect(intent[:handler]).to be_present, "expected #{verb} to map to a handler"
        expect(intent[:handler].name).to start_with("Pito::Chat::Handlers::")
        expect(intent[:known]).to be(true)
      end
    end
  end

  describe "aliases land on the same handler as their canonical" do
    {
      "ls"        => Pito::Chat::Handlers::List,
      "rm"        => Pito::Chat::Handlers::Delete,
      "analytics" => Pito::Chat::Handlers::Analyze,
      "stats"     => Pito::Chat::Handlers::Analyze
    }.each do |alias_token, handler|
      it "#{alias_token.inspect} → #{handler}" do
        expect(parsed_intent(alias_token)[:handler]).to eq(handler)
      end
    end
  end

  describe "unknown verbs fall to the not-known (NL/unknown) path" do
    [ "florp", "florp the wiggle", "xyzzy 123", "asdfgh" ].each do |input|
      it "#{input.inspect} → known: false" do
        expect(parsed_intent(input)).to include(stack: :chat, known: false)
      end
    end
  end
end
