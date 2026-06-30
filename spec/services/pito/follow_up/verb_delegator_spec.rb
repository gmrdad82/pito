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
      # detail (:system) + SimilarGames (:enhanced) + Channels (:enhanced) + the
      # at-a-glance (:enhanced, ALWAYS present — item 5).
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced, :enhanced, :enhanced ])
      detail = result.events.first[:payload].with_indifferent_access
      expect(detail[:game_id]).to eq(game.id)
    end

    it "produces the SAME events as the free-chat verb (chat ≡ #hashtag)" do
      free      = Pito::Chat::Dispatcher.call(input: "show game #{game.id}", conversation:)
      delegated = described_class.call(source_event:, rest: "show #{game.id}", conversation:)

      expect(delegated.events.map { |e| e[:kind] }).to eq(free.events.map { |e| e[:kind] })
      expect(delegated.events.first[:payload].with_indifferent_access[:game_id])
        .to eq(free.events.first[:payload].with_indifferent_access[:game_id])
    end

    it "adapts a not-found verb outcome to a NON-consuming Append (source stays repliable for a retry)" do
      result = described_class.call(source_event:, rest: "show 999999", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.consume).to be(false)
    end

    it "forwards channel / period / viewport_width into Chat::Dispatcher (D6/D7/D8)" do
      expect(Pito::Chat::Dispatcher).to receive(:call).with(
        hash_including(channel: "@xyz", period: "28d", viewport_width: "1024")
      ).and_return(Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: {} } ]))

      described_class.call(
        source_event:, rest: "show #{game.id}", conversation:,
        channel: "@xyz", period: "28d", viewport_width: "1024"
      )
    end

    it "rejects a verb that isn't an allowed reply action for the source message" do
      # game_list allows show/delete — `publish` is not in its matrix.
      result = described_class.call(source_event:, rest: "publish #{game.id}", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
      expect(result.message_args).to eq({ action: "publish" })
    end

    context "consume flag — link/unlink are repeatable, show/rm consume the source" do
      let(:channel)          { create(:channel) }
      let!(:video)           { create(:video, channel:) }
      # video_list source event — its declared actions include link and unlink.
      let(:video_list_event) do
        instance_double(Event, payload: { "reply_target" => "video_list" })
      end

      it "link produces Append with consume: false so the source card stays reusable" do
        result = described_class.call(
          source_event: video_list_event,
          rest:         "link #{video.id} to #{game.id}",
          conversation:
        )

        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(false)
      end

      it "unlink produces Append with consume: false so the source card stays reusable" do
        create(:video_game_link, video:, game:)

        result = described_class.call(
          source_event: video_list_event,
          rest:         "unlink #{video.id} from #{game.id}",
          conversation:
        )

        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(false)
      end

      it "show produces Append with consume: true (default — source is consumed)" do
        result = described_class.call(source_event:, rest: "show #{game.id}", conversation:)

        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(true)
      end

      it "rm produces Append with consume: true (default — source is consumed)" do
        result = described_class.call(source_event:, rest: "rm #{game.id}", conversation:)

        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(true)
      end
    end
  end
end
