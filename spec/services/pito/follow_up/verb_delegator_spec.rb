# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::VerbDelegator, type: :service do
  let(:conversation) { Conversation.singleton }
  # A game_list source event — its declared actions ("show", "delete") gate replies.
  let(:source_event) { instance_double(Event, payload: { "reply_target" => "game_list" }) }
  let!(:game)        { create(:game, title: "Dead Space") }

  describe ".call" do
    it "delegates `show <id>` to the Show verb handler and adapts to an Append" do
      result = described_class.call(source_event:, rest: "show #{game.id}", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
      detail = result.events.first[:payload].with_indifferent_access
      expect(detail[:game_id]).to eq(game.id)
    end

    it "produces the SAME events as the free-chat verb (chat ≡ #hashtag)" do
      free      = Pito::Chat::Dispatcher.call(input: "show #{game.id}", conversation:)
      delegated = described_class.call(source_event:, rest: "show #{game.id}", conversation:)

      expect(delegated.events.map { |e| e[:kind] }).to eq(free.events.map { |e| e[:kind] })
      expect(delegated.events.first[:payload].with_indifferent_access[:game_id])
        .to eq(free.events.first[:payload].with_indifferent_access[:game_id])
    end

    it "adapts a not-found verb outcome (still an Append with the system message)" do
      result = described_class.call(source_event:, rest: "show 999999", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "rejects a verb that isn't an allowed reply action for the source message (T18.5)" do
      # game_list allows show/delete — `publish` is not in its matrix.
      result = described_class.call(source_event:, rest: "publish #{game.id}", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
      expect(result.message_args).to eq({ action: "publish" })
    end
  end
end
