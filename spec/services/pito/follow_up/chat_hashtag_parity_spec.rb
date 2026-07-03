# frozen_string_literal: true

require "rails_helper"

# Parity contract: a verb reached via a `#<handle>` reply produces the SAME
# built+sent events as the same verb typed in free chat. The follow-up path runs
# the identical verb handler and only wraps the result, so the
# events match modulo the per-message random reply_handle / sampled copy.
#
# Locks the contract for ALL migrated verbs: show, show video, delete, link, unlink.
RSpec.describe "Chat ≡ #hashtag parity", type: :service do
  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Dead Space") }
  let!(:channel)     { create(:channel, handle: "@par", youtube_channel_id: "UCpar1") }
  let!(:video)       { create(:video, :public, title: "Boss Rush", channel:) }

  def free_events(input)
    Pito::Chat::Dispatcher.call(input:, conversation:).events
  end

  def reply_events(reply_target, rest, **extra)
    source = instance_double(Event, payload: { "reply_target" => reply_target }.merge(extra.transform_keys(&:to_s)))
    Pito::FollowUp::VerbDelegator.call(source_event: source, rest:, conversation:).events
  end

  it "`show game` → same kinds + same game (free-chat vs game_list reply)" do
    free  = free_events("show game #{game.id}")
    reply = reply_events("game_list", "show #{game.id}")

    # Bare show → detail only (plan-0.9.5 D3); parity between the two paths.
    expect(reply.map { |e| e[:kind] }).to eq(free.map { |e| e[:kind] }).and eq([ :system ])
    expect(reply.first[:payload].with_indifferent_access[:game_id])
      .to eq(free.first[:payload].with_indifferent_access[:game_id]).and eq(game.id)
  end

  it "`show video` → same kinds + same video (free-chat vs video_list reply)" do
    free  = free_events("show video #{video.id}")
    reply = reply_events("video_list", "show #{video.id}")

    expect(reply.map { |e| e[:kind] }).to eq(free.map { |e| e[:kind] }).and eq([ :system ])
    expect(reply.first[:payload].with_indifferent_access[:video_id])
      .to eq(free.first[:payload].with_indifferent_access[:video_id]).and eq(video.id)
  end

  it "`delete` → same single confirmation event (free-chat vs game_list reply)" do
    free  = free_events("delete game #{game.id}")
    reply = reply_events("game_list", "delete #{game.id}")

    expect(reply.map { |e| e[:kind] }).to eq(free.map { |e| e[:kind] }).and eq([ :confirmation ])
  end

  it "`link` → :system ack + link created, both ways (free-chat vs game_detail reply)" do
    free = free_events("link game #{game.id} to video #{video.id}")
    expect(free.map { |e| e[:kind] }).to eq([ :system ])
    expect(VideoGameLink.exists?(game:, video:)).to be(true)

    VideoGameLink.where(game:, video:).delete_all
    reply = reply_events("game_detail", "link video #{video.id}", game_id: game.id)
    expect(reply.map { |e| e[:kind] }).to eq([ :system ])
    expect(VideoGameLink.exists?(game:, video:)).to be(true)
  end

  it "`unlink` → :system ack + link removed, both ways (free-chat vs game_detail reply)" do
    VideoGameLink.find_or_create_by!(game:, video:)
    free = free_events("unlink game #{game.id} from video #{video.id}")
    expect(free.map { |e| e[:kind] }).to eq([ :system ])
    expect(VideoGameLink.exists?(game:, video:)).to be(false)

    VideoGameLink.find_or_create_by!(game:, video:)
    reply = reply_events("game_detail", "unlink video #{video.id}", game_id: game.id)
    expect(reply.map { |e| e[:kind] }).to eq([ :system ])
    expect(VideoGameLink.exists?(game:, video:)).to be(false)
  end

  it "`reindex video` → same single confirmation event (free-chat vs video_detail reply)" do
    free  = free_events("reindex video #{video.id}")
    reply = reply_events("video_detail", "reindex video #{video.id}", video_id: video.id)

    expect(reply.map { |e| e[:kind] }).to eq(free.map { |e| e[:kind] }).and eq([ :confirmation ])
    expect(reply.first[:payload]["command"]).to eq("video_reindex")
  end
end
