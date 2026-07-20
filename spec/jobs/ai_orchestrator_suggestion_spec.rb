# frozen_string_literal: true

require "rails_helper"

# Pins the "@ai closes actionable answers with valid suggestions" change
# (SYSTEM_PROMPT now instructs the model to CLOSE WITH A SUGGESTION as the
# EXPECTED default for actionable answers, config/pito/content.yml's suggestion
# block was reconciled to match, and AiOrchestratorJob grew a hand-verified
# CHEAT-SHEET of command shapes for the model to pick suggestions from).
#
# This is a REGRESSION GUARD, not a unit spec for either file: it proves the
# cheat-sheet the prompt promises is actually made of commands that resolve
# through the SAME gate Ai::Blocks uses to accept/degrade a suggestion
# (Pito::Dispatch::UniversalReply.chat_tool) — if a future edit turns a
# COMMAND_SHAPES line into invalid syntax, this fails.
RSpec.describe "AI orchestrator suggestion closing" do
  let(:conversation) { Conversation.singleton }
  let(:game)         { create(:game) }
  let(:video)        { create(:video) }
  let(:channel)      { create(:channel, handle: "pitotest") }

  # Turns a curated shape ("update vid description <id> <text>") into a
  # concrete, runnable command by substituting each placeholder with a real
  # id/handle/word — tracking the nearest preceding noun keyword (game/vid/
  # channel) so <id> picks the RIGHT record's id even when it isn't directly
  # adjacent to the noun (e.g. "update game footage <id> <hours>").
  def concrete_command_for(shape)
    last_noun = nil

    shape.split(" ").map do |word|
      last_noun = :game    if word == "game"
      last_noun = :vid     if word == "vid"
      last_noun = :channel if word == "channel"

      case word
      when "<id>"        then (last_noun == :vid ? video.id : game.id).to_s
      when "@handle"     then channel.at_handle
      when "<text>", "<title>", "<name>" then "word"
      when "<hours>"     then "8.5"
      when "<amount>"    then "59.99"
      when "<dd-mm-yyyy>" then 7.days.from_now.strftime("%d-%m-%Y")
      when "<hh:mm>"      then "18:00"
      else word
      end
    end.join(" ")
  end

  describe "AiOrchestratorJob.system_prompt" do
    it "carries the CHEAT-SHEET of hand-verified command shapes" do
      prompt = AiOrchestratorJob.system_prompt

      expect(prompt).to match(/CHEAT-SHEET/)
      expect(prompt).to include("show game <id>")
      expect(prompt).to include("link game <id> to vid <id>")
    end

    it "instructs the model that closing with a suggestion is the expected default for actionable answers" do
      prompt = AiOrchestratorJob.system_prompt

      expect(prompt).to match(/CLOSE WITH A SUGGESTION/)
      expect(prompt).to match(/EXPECTED close/)
    end

    it "carries the content.yml suggestion block's reconciled expected-default framing" do
      description = Ai::ContentRegistry.respond_description

      expect(description).to match(/EXPECTED default/)
    end
  end

  describe "AiOrchestratorJob::COMMAND_SHAPES" do
    it "resolves every advertised shape to a real tool through the same gate blocks.rb uses" do
      unresolved = AiOrchestratorJob::COMMAND_SHAPES.flat_map { |line| line.split("|").map(&:strip) }
        .filter_map do |shape|
          concrete = concrete_command_for(shape)
          tool = Pito::Dispatch::UniversalReply.chat_tool(concrete, conversation)
          "#{shape.inspect} => #{concrete.inspect} (tool=#{tool.inspect})" if tool.blank? || tool == "unknown"
        end

      expect(unresolved).to eq([]), "unresolved COMMAND_SHAPES entries:\n#{unresolved.join("\n")}"
    end
  end

  describe "the suggestion validity gate (Ai::Blocks — what the cheat-sheet promise cashes out to)" do
    it "keeps a suggestion whose command resolves and degrades one whose command doesn't" do
      result = Ai::Blocks.normalize([
        { "type" => "suggestion", "command" => "show game #{game.id}" },
        { "type" => "suggestion", "command" => "frobnicate the moonbeams" }
      ], conversation: conversation)

      expect(result[0]).to eq({ "type" => "suggestion", "command" => "show game #{game.id}" })
      expect(result[1]["type"]).to eq("text")
      expect(result[1]["text"]).to include("frobnicate the moonbeams")
    end
  end

  describe "the max_per_answer cap (content.yml suggestion.limits.max_per_answer)" do
    it "keeps only the configured max of otherwise-valid suggestions, degrading the rest" do
      cap    = Ai::Blocks.max_suggestions
      blocks = Array.new(cap + 1) { { "type" => "suggestion", "command" => "show game #{game.id}" } }

      result = Ai::Blocks.normalize(blocks, conversation: conversation)

      expect(result.first(cap)).to all(include("type" => "suggestion"))
      expect(result[cap]["type"]).to eq("text")
      expect(result.size).to eq(cap + 1)
    end
  end
end
