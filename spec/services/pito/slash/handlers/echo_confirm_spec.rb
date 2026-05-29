# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::EchoConfirm, type: :service do
  describe "#call" do
    it "returns a Result::NeedsConfirmation" do
      conversation = Conversation.create!
      invocation = Pito::Slash::Invocation.new(
        verb: :confirm_demo,
        args: [],
        kwargs: {},
        raw: "/confirm_demo"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call

      expect(result).to be_a(Pito::Slash::Result::NeedsConfirmation)
    end

    it "carries the expected prompt_key, prompt_args, and command_text" do
      conversation = Conversation.create!
      invocation = Pito::Slash::Invocation.new(
        verb: :confirm_demo,
        args: [],
        kwargs: {},
        raw: "/confirm_demo"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call

      expect(result.prompt_key).to eq("pito.slash.confirm_demo.prompt")
      expect(result.prompt_args).to eq({})
      expect(result.command_text).to eq("/confirm_demo")
    end
  end
end
