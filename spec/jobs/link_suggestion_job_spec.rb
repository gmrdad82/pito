# frozen_string_literal: true

require "rails_helper"

RSpec.describe LinkSuggestionJob, type: :job do
  let(:video) { create(:video, title: "Elden Ring: Shadow of the Erdtree") }

  it "is a no-op when the video id is missing" do
    expect(Video::GameLinkSuggester).not_to receive(:call)
    expect(Pito::Notifications::Source::LinkSuggestion).not_to receive(:report!)

    expect { described_class.new.perform(0) }.not_to change(Notification, :count)
  end

  it "skips an already-linked video without calling the suggester" do
    game = create(:game)
    create(:video_game_link, video: video, game: game)

    expect(Video::GameLinkSuggester).not_to receive(:call)

    expect { described_class.new.perform(video.id) }.not_to change(Notification, :count)
    expect(video.reload.link_suggested_at).to be_nil
  end

  it "skips a video already offered a suggestion" do
    video.update_column(:link_suggested_at, 1.day.ago)

    expect(Video::GameLinkSuggester).not_to receive(:call)

    expect { described_class.new.perform(video.id) }.not_to change(Notification, :count)
  end

  it "does not stamp link_suggested_at when the suggester finds no candidates" do
    allow(Video::GameLinkSuggester).to receive(:call).with(video).and_return([])

    expect { described_class.new.perform(video.id) }.not_to change(Notification, :count)
    expect(video.reload.link_suggested_at).to be_nil
  end

  it "stamps link_suggested_at and reports one notification on the happy path" do
    game_one = create(:game, title: "Elden Ring")
    game_two = create(:game, title: "Elden Ring: Nightreign")
    allow(Video::GameLinkSuggester).to receive(:call).with(video).and_return([ game_one, game_two ])

    expect { described_class.new.perform(video.id) }.to change(Notification, :count).by(1)

    expect(video.reload.link_suggested_at).to be_present

    notification = Notification.last
    expect(notification.message).to include("Elden Ring")
    expect(notification.message).to include("Elden Ring: Nightreign")
    expect(notification.message).to include("link vid #{video.id} to game #{game_one.id}")
    expect(notification.message).to include("link vid #{video.id} to game #{game_two.id}")
  end

  it "only ever reports once, even if perform runs again after stamping" do
    game = create(:game, title: "Elden Ring")
    allow(Video::GameLinkSuggester).to receive(:call).with(video).and_return([ game ])

    described_class.new.perform(video.id)
    expect { described_class.new.perform(video.id) }.not_to change(Notification, :count)
  end
end
