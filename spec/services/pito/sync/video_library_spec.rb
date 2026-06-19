# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sync::VideoLibrary, type: :service do
  include ActiveJob::TestHelper

  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha Channel")
  end

  let(:client) { instance_double(Channel::Youtube::Client) }

  let(:videos_list_response) do
    {
      items: [
        {
          id: "vid1",
          snippet: {
            title: "Video One",
            description: "Desc one",
            tags: [ "tag1" ],
            category_id: "20",
            published_at: "2024-01-01T00:00:00Z",
            thumbnails: { high: { url: "http://example.com/v1.jpg" } }
          },
          statistics: { view_count: "1000", like_count: "50", comment_count: "10" },
          content_details: { duration: "PT5M30S" },
          status: { privacy_status: "public" }
        },
        {
          id: "vid2",
          snippet: {
            title: "Video Two",
            description: "Desc two",
            tags: [],
            category_id: "20",
            published_at: "2024-02-01T00:00:00Z",
            thumbnails: { high: { url: "http://example.com/v2.jpg" } }
          },
          statistics: { view_count: "500", like_count: "25", comment_count: "5" },
          content_details: { duration: "PT10M" },
          status: { privacy_status: "public" }
        }
      ]
    }
  end

  before do
    allow(Channel::Youtube::Client).to receive(:new).and_return(client)
    allow(client).to receive(:videos_list).and_return(videos_list_response)
  end

  subject(:service) { described_class.new(channel) }

  describe "#import_new" do
    # A pre-existing locally-known upload bounds the search and is the id
    # discovery should skip on a re-run.
    let!(:existing_video) do
      create(:video,
             channel: channel,
             youtube_video_id: "vid1",
             published_at: Time.utc(2024, 1, 1))
    end

    let(:search_response) do
      {
        items: [
          { id: { video_id: "vid1" } },
          { id: { video_id: "vidnew" } }
        ],
        next_page_token: nil
      }
    end

    let(:new_video_details) do
      {
        items: [
          {
            id: "vidnew",
            snippet: {
              title: "Private New",
              description: "Hidden upload",
              tags: [],
              category_id: "20",
              published_at: "2024-06-01T00:00:00Z",
              thumbnails: { high: { url: "http://example.com/new.jpg" } }
            },
            statistics: { view_count: "0", like_count: "0", comment_count: "0" },
            content_details: { duration: "PT1M" },
            status: { privacy_status: "private" }
          }
        ]
      }
    end

    before do
      allow(client).to receive(:search_list).and_return(search_response)
      allow(client).to receive(:videos_list).and_return(new_video_details)
    end

    it "imports a new (private) video not already in the DB" do
      expect { service.import_new }.to change(Video, :count).by(1)

      created = Video.find_by(youtube_video_id: "vidnew")
      expect(created).to be_present
      expect(created.title).to eq("Private New")
      expect(created.privacy_status).to eq("private")
    end

    it "returns a Result counting only the newly-created video" do
      result = service.import_new

      expect(result).to be_a(described_class::Result)
      expect(result.imported).to eq(1)
      expect(result.titles).to contain_exactly("Private New")
      expect(result.updated).to eq(0)
      expect(result.deleted).to eq(0)
    end

    it "skips ids already present in the DB" do
      service.import_new

      # vid1 was already present, so only vidnew's details are fetched.
      expect(client).to have_received(:videos_list).with(
        hash_including(ids: [ "vidnew" ])
      )
    end

    it "does not re-import when every discovered id already exists" do
      allow(client).to receive(:search_list).and_return(
        { items: [ { id: { video_id: "vid1" } } ], next_page_token: nil }
      )

      result = nil
      expect { result = service.import_new }.not_to change(Video, :count)
      expect(result.imported).to eq(0)
      expect(client).not_to have_received(:videos_list)
    end

    it "bounds the search with the max local published_at" do
      service.import_new

      expect(client).to have_received(:search_list).with(
        hash_including(
          for_mine: true,
          type: "video",
          order: "date",
          published_after: Time.utc(2024, 1, 1)
        )
      )
    end

    it "paginates search results across pages" do
      allow(client).to receive(:search_list).and_return(
        { items: [ { id: { video_id: "vid1" } } ], next_page_token: "PAGE2" },
        { items: [ { id: { video_id: "vidnew" } } ], next_page_token: nil }
      )

      service.import_new

      expect(client).to have_received(:search_list).twice
    end

    it "discovers the full library with no lower bound on a channel's first run" do
      existing_video.destroy!
      allow(client).to receive(:search_list).and_return(
        { items: [ { id: { video_id: "vidnew" } } ], next_page_token: nil }
      )

      expect { service.import_new }.to change(Video, :count).by(1)
      expect(client).to have_received(:search_list).with(
        hash_including(published_after: nil)
      )
    end

    it "returns an empty Result when the channel has no connection" do
      orphan = create(:channel)
      result = described_class.new(orphan).import_new

      expect(result.imported).to eq(0)
      expect(result.titles).to be_empty
    end
  end

  describe "#sync" do
    # An existing upload reconcile will UPDATE (title changed upstream) and one it
    # will DELETE (absent from the reconcile response), plus a brand-new id only
    # discovery finds — so the merged Result carries all three counters.
    let!(:keep) do
      create(:video,
             channel: channel,
             youtube_video_id: "keep1",
             title: "Keep Old",
             description: "Body",
             privacy_status: :public,
             tags: [ "a" ],
             category_id: "20",
             duration_seconds: 60,
             published_at: Time.utc(2024, 1, 1))
    end

    let!(:gone) do
      create(:video,
             channel: channel,
             youtube_video_id: "gone1",
             title: "Gone Upstream",
             published_at: Time.utc(2024, 2, 1))
    end

    # One canonical item for the brand-new video, reused by BOTH the import fetch
    # and the reconcile listing so reconcile re-reads it as :unchanged.
    let(:newvid_item) do
      {
        id: "newvid",
        snippet: {
          title: "Brand New",
          description: "Fresh upload",
          tags: [],
          category_id: "20",
          published_at: "2024-06-01T00:00:00Z",
          thumbnails: { high: { url: "http://example.com/new.jpg" } }
        },
        statistics: { view_count: "0", like_count: "0", comment_count: "0" },
        content_details: { duration: "PT1M" },
        status: { privacy_status: "public" }
      }
    end

    let(:keep_updated_item) do
      {
        id: "keep1",
        snippet: {
          title: "Keep New",
          description: "Body",
          tags: [ "a" ],
          category_id: "20",
          published_at: "2024-01-01T00:00:00Z",
          thumbnails: { high: { url: "http://example.com/keep1.jpg" } }
        },
        statistics: { view_count: "0", like_count: "0", comment_count: "0" },
        content_details: { duration: "PT1M" },
        status: { privacy_status: "public" }
      }
    end

    before do
      allow(client).to receive(:search_list).and_return(
        {
          items: [
            { id: { video_id: "keep1" } },
            { id: { video_id: "gone1" } },
            { id: { video_id: "newvid" } }
          ],
          next_page_token: nil
        }
      )
      # Default (reconcile): list the still-existing ids; gone1 is absent → deleted.
      allow(client).to receive(:videos_list)
        .and_return({ items: [ keep_updated_item, newvid_item ] })
      # import_new fetches ONLY the brand-new id.
      allow(client).to receive(:videos_list)
        .with(hash_including(ids: [ "newvid" ]))
        .and_return({ items: [ newvid_item ] })
    end

    it "imports new uploads, reconciles existing rows, and merges both passes" do
      result = service.sync

      expect(result).to be_a(described_class::Result)
      expect(result.imported).to eq(1)
      expect(result.updated).to eq(1)
      expect(result.deleted).to eq(1)
      expect(result.titles).to contain_exactly("Brand New", "Gone Upstream")
    end

    it "creates the newly-discovered upload and hard-deletes the removed one" do
      service.sync

      expect(Video.exists?(youtube_video_id: "newvid")).to be(true)
      expect(Video.exists?(gone.id)).to be(false)
      expect(keep.reload.title).to eq("Keep New")
    end
  end

  describe "#refresh" do
    let!(:existing) do
      create(:video,
             channel: channel,
             youtube_video_id: "ref1",
             title: "Old Title",
             published_at: Time.utc(2024, 1, 1))
    end

    let(:refresh_response) do
      {
        items: [
          {
            id: "ref1",
            snippet: {
              title: "New Title",
              description: "Body",
              tags: [],
              category_id: "20",
              published_at: "2024-01-01T00:00:00Z",
              thumbnails: { high: { url: "http://example.com/ref1.jpg" } }
            },
            statistics: { view_count: "10", like_count: "2", comment_count: "1" },
            content_details: { duration: "PT1M" },
            status: { privacy_status: "public" }
          }
        ]
      }
    end

    before do
      allow(client).to receive(:videos_list).and_return(refresh_response)
    end

    it "fetches the given ids via videos.list and upserts them" do
      service.refresh([ "ref1" ])

      expect(client).to have_received(:videos_list).with(hash_including(ids: [ "ref1" ]))
      expect(existing.reload.title).to eq("New Title")
    end

    it "returns a Result counting updated rows, with no imports or deletions" do
      result = service.refresh([ "ref1" ])

      expect(result).to be_a(described_class::Result)
      expect(result.imported).to eq(0)
      expect(result.updated).to eq(1)
      expect(result.deleted).to eq(0)
      expect(result.titles).to be_empty
    end

    it "does not discover or delete videos outside the id list" do
      other = create(:video, channel: channel, youtube_video_id: "other1", published_at: Time.utc(2024, 2, 1))

      service.refresh([ "ref1" ])

      expect(Video.exists?(other.id)).to be(true)
    end

    it "returns an empty Result for a blank id list" do
      result = service.refresh([])

      expect(result.updated).to eq(0)
      expect(client).not_to have_received(:videos_list)
    end
  end

  describe "#upsert" do
    let(:attrs) do
      {
        youtube_video_id: "vid9",
        title:            "Solo",
        description:      "Body",
        privacy_status:   :public,
        tags:             [ "x" ],
        category_id:      "20",
        duration_seconds: 60,
        view_count:       7,
        like_count:       3,
        comment_count:    1,
        thumbnail_url:    "http://example.com/v9.jpg"
      }
    end

    it "returns :created and creates a row on first upsert" do
      expect(service.upsert(attrs.dup)).to eq(:created)
      expect(Video.find_by(youtube_video_id: "vid9")).to be_present
    end

    it "returns :unchanged on a subsequent unchanged upsert" do
      service.upsert(attrs.dup)

      expect(service.upsert(attrs.dup)).to eq(:unchanged)
    end

    it "returns :updated when an existing row's attributes change" do
      service.upsert(attrs.dup)

      expect(service.upsert(attrs.merge(title: "Renamed"))).to eq(:updated)
      expect(Video.find_by(youtube_video_id: "vid9").title).to eq("Renamed")
    end

    it "returns :unchanged for blank youtube_video_id" do
      expect(service.upsert(attrs.merge(youtube_video_id: nil))).to eq(:unchanged)
    end
  end

  describe "#reconcile" do
    # Three locally-known videos. `keep_unchanged` round-trips identical, so
    # reconcile leaves it alone; `keep_changed` comes back with a new title;
    # `gone` is deliberately ABSENT from the videos.list response (deleted on
    # YouTube) and must be hard-deleted with its links + stats.
    let(:game) { create(:game) }

    let!(:keep_unchanged) do
      create(:video,
             channel: channel,
             youtube_video_id: "keep1",
             title: "Keep One",
             description: "Body one",
             privacy_status: :public,
             tags: [ "a" ],
             category_id: "20",
             duration_seconds: 60,
             published_at: Time.utc(2024, 1, 1))
    end

    let!(:keep_changed) do
      create(:video,
             channel: channel,
             youtube_video_id: "keep2",
             title: "Old Title",
             description: "Body two",
             privacy_status: :public,
             tags: [ "b" ],
             category_id: "20",
             duration_seconds: 120,
             published_at: Time.utc(2024, 2, 1))
    end

    let!(:gone) do
      create(:video,
             channel: channel,
             youtube_video_id: "gone1",
             title: "Deleted Upstream",
             published_at: Time.utc(2024, 3, 1))
    end

    let!(:gone_link) { create(:video_game_link, video: gone, game: game) }

    let(:reconcile_response) do
      {
        items: [
          {
            id: "keep1",
            snippet: {
              title: "Keep One",
              description: "Body one",
              tags: [ "a" ],
              category_id: "20",
              published_at: "2024-01-01T00:00:00Z",
              thumbnails: { high: { url: "http://example.com/keep1.jpg" } }
            },
            statistics: { view_count: "0", like_count: "0", comment_count: "0" },
            content_details: { duration: "PT1M" },
            status: { privacy_status: "public" }
          },
          {
            id: "keep2",
            snippet: {
              title: "New Title",
              description: "Body two",
              tags: [ "b" ],
              category_id: "20",
              published_at: "2024-02-01T00:00:00Z",
              thumbnails: { high: { url: "http://example.com/keep2.jpg" } }
            },
            statistics: { view_count: "0", like_count: "0", comment_count: "0" },
            content_details: { duration: "PT2M" },
            status: { privacy_status: "public" }
          }
        ]
      }
    end

    before do
      # Round-trip keep_unchanged once so its attrs already match the response
      # (otherwise the first reconcile would count it as :updated).
      Pito::Stats.set(keep_unchanged, :views, 0)
      Pito::Stats.set(keep_unchanged, :likes, 0)
      Pito::Stats.set(keep_unchanged, :comments, 0)
      allow(client).to receive(:videos_list).and_return(reconcile_response)
    end

    it "hard-deletes a video YouTube no longer returns" do
      service.reconcile

      expect(Video.exists?(gone.id)).to be(false)
    end

    it "cascades the deleted video's links and stats" do
      Pito::Stats.set(gone, :views, 99)
      link_id = gone_link.id

      service.reconcile

      expect(VideoGameLink.exists?(link_id)).to be(false)
      expect(Stat.where(entity_type: "Video", entity_id: gone.id)).to be_empty
    end

    it "enqueues a GameStatsRefreshJob for each linked game of a deleted video" do
      expect { service.reconcile }
        .to have_enqueued_job(GameStatsRefreshJob).with(game.id).at_least(:once)
    end

    it "updates a returned video whose attributes changed" do
      service.reconcile

      expect(keep_changed.reload.title).to eq("New Title")
      expect(Video.exists?(keep_changed.id)).to be(true)
    end

    it "leaves a returned-unchanged video untouched and un-indexed" do
      expect { service.reconcile }.not_to have_enqueued_job(VideoVoyageIndexJob).with(keep_unchanged.id)
      expect(Video.exists?(keep_unchanged.id)).to be(true)
    end

    it "returns a Result counting updates and deletions" do
      result = service.reconcile

      expect(result).to be_a(described_class::Result)
      expect(result.imported).to eq(0)
      expect(result.updated).to eq(1)
      expect(result.deleted).to eq(1)
      expect(result.titles).to contain_exactly("Deleted Upstream")
    end

    it "returns an empty Result when the channel has no videos" do
      Video.where(channel: channel).destroy_all
      result = described_class.new(channel).reconcile

      expect(result.updated).to eq(0)
      expect(result.deleted).to eq(0)
      expect(result.titles).to be_empty
    end

    it "skips deletion when the videos.list call fails" do
      allow(client).to receive(:videos_list).and_raise(StandardError, "API down")

      expect { service.reconcile }.not_to change(Video, :count)
    end
  end
end
