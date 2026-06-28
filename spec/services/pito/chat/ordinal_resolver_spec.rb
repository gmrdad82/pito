# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::OrdinalResolver do
  def call(entity:, ordinal:, filters: {}, channel_scope: nil)
    described_class.call(entity:, ordinal:, filters:, channel_scope:)
  end

  # ── Games ────────────────────────────────────────────────────────────────────

  describe "entity: :game" do
    # Helper: create a game with a fully specified release_date.
    # The before_save callback derives release_date from year/month/day.
    def game_with_date(year, month, day, **attrs)
      create(:game, release_year: year, release_month: month, release_day: day, **attrs)
    end

    context "ordinal ordering by release_date" do
      let!(:game_old)  { game_with_date(2018, 1, 1,  title: "Old Game") }
      let!(:game_mid)  { game_with_date(2020, 6, 15, title: "Mid Game") }
      let!(:game_new)  { game_with_date(2023, 12, 25, title: "New Game") }
      let!(:game_nodot) { create(:game, title: "TBA Game") }  # no release_date → NULLS LAST

      it ":first returns the game with the earliest release_date" do
        expect(call(entity: :game, ordinal: :first)).to eq(game_old)
      end

      it ":last returns the game with the latest release_date" do
        expect(call(entity: :game, ordinal: :last)).to eq(game_new)
      end

      it "a game with no release_date is never picked as first (NULLS LAST in ASC)" do
        expect(call(entity: :game, ordinal: :first)).not_to eq(game_nodot)
      end

      it "a game with no release_date is never picked as last (NULLS LAST in DESC)" do
        expect(call(entity: :game, ordinal: :last)).not_to eq(game_nodot)
      end
    end

    context "genre filter" do
      let!(:genre_rpg)     { create(:genre, name: "Role-playing") }
      let!(:genre_shooter) { create(:genre, name: "Shooter") }
      let!(:rpg_old)   { game_with_date(2018, 3, 1,  title: "Old RPG") }
      let!(:rpg_new)   { game_with_date(2022, 9, 15, title: "New RPG") }
      let!(:shooter)   { game_with_date(2020, 7, 4,  title: "Shooter Game") }

      before do
        create(:game_genre, game: rpg_old,  genre: genre_rpg,     position: 1)
        create(:game_genre, game: rpg_new,  genre: genre_rpg,     position: 1)
        create(:game_genre, game: shooter,  genre: genre_shooter, position: 1)
      end

      it ":first with genre filter returns earliest matching game" do
        result = call(entity: :game, ordinal: :first, filters: { genre: "Role-playing" })
        expect(result).to eq(rpg_old)
      end

      it ":last with genre filter returns latest matching game" do
        result = call(entity: :game, ordinal: :last, filters: { genre: "Role-playing" })
        expect(result).to eq(rpg_new)
      end

      it "genre filter excludes non-matching games" do
        result = call(entity: :game, ordinal: :last, filters: { genre: "Role-playing" })
        expect(result).not_to eq(shooter)
      end

      it "returns nil when no game matches the genre filter" do
        result = call(entity: :game, ordinal: :last, filters: { genre: "Racing" })
        expect(result).to be_nil
      end
    end

    context "channel scope" do
      let!(:channel)     { create(:channel, handle: "@testchan") }
      let!(:other_chan)  { create(:channel, handle: "@otherchan") }
      let!(:linked_vid)  { create(:video, channel: channel) }
      let!(:other_vid)   { create(:video, channel: other_chan) }
      let!(:linked_game) { game_with_date(2021, 3, 10, title: "Linked Game") }
      let!(:other_game)  { game_with_date(2019, 5, 20, title: "Other Game") }

      before do
        create(:video_game_link, video: linked_vid, game: linked_game)
        create(:video_game_link, video: other_vid,  game: other_game)
      end

      it "scopes to games linked to videos on the specified channel" do
        result = call(entity: :game, ordinal: :last, channel_scope: "@testchan")
        expect(result).to eq(linked_game)
      end

      it "excludes games linked only to other channels" do
        result = call(entity: :game, ordinal: :last, channel_scope: "@testchan")
        expect(result).not_to eq(other_game)
      end

      it "@all channel scope returns all games (no channel filter)" do
        result = call(entity: :game, ordinal: :last, channel_scope: "@all")
        expect(result).not_to be_nil
      end

      it "nil channel_scope returns all games (no channel filter)" do
        result = call(entity: :game, ordinal: :last, channel_scope: nil)
        expect(result).not_to be_nil
      end

      it "unknown handle returns nil" do
        result = call(entity: :game, ordinal: :last, channel_scope: "@nope")
        expect(result).to be_nil
      end

      it "handle without @ prefix is normalized and matched" do
        result = call(entity: :game, ordinal: :last, channel_scope: "testchan")
        expect(result).to eq(linked_game)
      end
    end
  end

  # ── Videos ───────────────────────────────────────────────────────────────────

  describe "entity: :video" do
    let!(:channel) { create(:channel, handle: "@testchan") }

    context "ordinal ordering by published_at (default privacy: published)" do
      let!(:vid_old) { create(:video, :public, channel: channel, title: "Old Vid", published_at: 2.years.ago) }
      let!(:vid_new) { create(:video, :public, channel: channel, title: "New Vid", published_at: 1.day.ago) }

      it ":last (no filter) defaults to published — returns latest published video" do
        expect(call(entity: :video, ordinal: :last)).to eq(vid_new)
      end

      it ":first (no filter) defaults to published — returns earliest published video" do
        expect(call(entity: :video, ordinal: :first)).to eq(vid_old)
      end

      it ":last with explicit privacy :published returns latest public video" do
        result = call(entity: :video, ordinal: :last, filters: { privacy: :published })
        expect(result).to eq(vid_new)
      end
    end

    context "show last vid alias = show last published vid" do
      let!(:vid_pub)      { create(:video, :public,   channel: channel, published_at: 1.day.ago) }
      let!(:vid_unlisted) { create(:video, :unlisted, channel: channel) }

      it "no filter → returns published video (not unlisted)" do
        result = call(entity: :video, ordinal: :last)
        expect(result).to eq(vid_pub)
      end
    end

    context "privacy filter: unlisted" do
      let!(:vid_pub)      { create(:video, :public,   channel: channel, published_at: 2.days.ago) }
      let!(:vid_unlisted) { create(:video, :unlisted, channel: channel, title: "Unlisted Vid") }

      it ":last with privacy :unlisted returns the unlisted video" do
        result = call(entity: :video, ordinal: :last, filters: { privacy: :unlisted })
        expect(result).to eq(vid_unlisted)
      end

      it ":last with privacy :unlisted excludes public videos" do
        result = call(entity: :video, ordinal: :last, filters: { privacy: :unlisted })
        expect(result).not_to eq(vid_pub)
      end
    end

    context "privacy filter: private" do
      let!(:vid_pub)     { create(:video, :public,  channel: channel, published_at: 1.day.ago) }
      let!(:vid_private) { create(:video, :private, channel: channel, title: "Private Vid") }

      it ":last with privacy :privacy_status_private returns the private video" do
        result = call(entity: :video, ordinal: :last, filters: { privacy: :privacy_status_private })
        expect(result).to eq(vid_private)
      end
    end

    context "returns nil when no video matches the filter" do
      let!(:vid_pub) { create(:video, :public, channel: channel) }

      it "returns nil when no private video exists and filter is :privacy_status_private" do
        result = call(entity: :video, ordinal: :last, filters: { privacy: :privacy_status_private })
        expect(result).to be_nil
      end
    end

    context "channel scope" do
      let!(:other_chan)   { create(:channel, handle: "@otherchan") }
      let!(:vid_on_test)  { create(:video, :public, channel: channel,    title: "Test Chan Vid", published_at: 1.day.ago) }
      let!(:vid_on_other) { create(:video, :public, channel: other_chan,  title: "Other Chan Vid", published_at: 3.days.ago) }

      it "scopes to the specified channel's videos" do
        result = call(entity: :video, ordinal: :last, channel_scope: "@testchan")
        expect(result).to eq(vid_on_test)
        expect(result.channel_id).to eq(channel.id)
      end

      it "excludes videos from other channels" do
        result = call(entity: :video, ordinal: :last, channel_scope: "@testchan")
        expect(result).not_to eq(vid_on_other)
      end

      it "@all channel scope returns videos from all channels" do
        result = call(entity: :video, ordinal: :last, channel_scope: "@all")
        expect(result).not_to be_nil
      end

      it "nil channel_scope returns videos from all channels" do
        result = call(entity: :video, ordinal: :last, channel_scope: nil)
        expect(result).not_to be_nil
      end

      it "unknown handle returns nil" do
        result = call(entity: :video, ordinal: :last, channel_scope: "@nope")
        expect(result).to be_nil
      end

      it "handle without @ prefix is normalized and matched" do
        result = call(entity: :video, ordinal: :last, channel_scope: "testchan")
        expect(result).to eq(vid_on_test)
      end
    end
  end
end
