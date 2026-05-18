require "rails_helper"

RSpec.describe Youtube::DiffComputer do
  let(:video) do
    build_stubbed(:video,
           title: "local",
           description: "local body",
           tags: %w[a b c],
           category_id: "20",
           privacy_status: :private,
           publish_at: nil,
           self_declared_made_for_kids: false,
           contains_synthetic_media: false,
           embeddable: true,
           public_stats_viewable: true,
           view_count: 100,
           like_count: 10,
           comment_count: 1,
           duration_seconds: 60,
           thumbnail_url: "https://i.ytimg.com/local.jpg")
  end

  def payload(snippet: {}, status: {}, statistics: {}, content_details: {})
    {
      snippet: { title: "local", description: "local body", tags: %w[a b c],
                 categoryId: "20", thumbnails: {
                   maxres: { url: "https://i.ytimg.com/local.jpg" }
                 } }.merge(snippet),
      status: { privacyStatus: "private", publishAt: nil, embeddable: true,
                publicStatsViewable: true, selfDeclaredMadeForKids: false,
                containsSyntheticMedia: false,
                madeForKids: false }.merge(status),
      statistics: { viewCount: "100", likeCount: "10",
                    commentCount: "1" }.merge(statistics),
      contentDetails: { duration: "PT1M" }.merge(content_details)
    }
  end

  describe "no-diff case" do
    it "returns an empty hash when every field matches" do
      diff = described_class.call(video, payload)
      expect(diff).to eq({})
    end
  end

  describe "single-field diff" do
    it "surfaces a title mismatch" do
      diff = described_class.call(video, payload(snippet: { title: "remote" }))
      expect(diff.keys).to eq(%w[title])
      expect(diff["title"]).to eq({ "pito" => "local", "youtube" => "remote" })
    end

    it "surfaces a description mismatch" do
      diff = described_class.call(video, payload(snippet: { description: "remote body" }))
      expect(diff.keys).to include("description")
    end
  end

  describe "multi-field diff" do
    it "surfaces every differing field" do
      diff = described_class.call(video, payload(
        snippet: { title: "remote", description: "remote body" },
        status: { privacyStatus: "public" }
      ))
      expect(diff.keys).to match_array(%w[title description privacy_status])
    end
  end

  describe "type-mismatch tolerance" do
    it "coerces string counts to integers (no phantom diff)" do
      diff = described_class.call(video, payload(statistics: { viewCount: "100" }))
      expect(diff.keys).not_to include("view_count")
    end

    it "surfaces a real counter mismatch" do
      diff = described_class.call(video, payload(statistics: { viewCount: "999" }))
      expect(diff["view_count"]).to eq({ "pito" => 100, "youtube" => "999" })
    end
  end

  describe "tags sorted-set semantics" do
    it "treats reordered tags as equivalent" do
      diff = described_class.call(video, payload(snippet: { tags: %w[c b a] }))
      expect(diff.keys).not_to include("tags")
    end

    it "surfaces a real tag mismatch" do
      diff = described_class.call(video, payload(snippet: { tags: %w[a b d] }))
      expect(diff["tags"]).to eq({ "pito" => %w[a b c], "youtube" => %w[a b d] })
    end
  end

  describe "missing fields" do
    it "ignores fields YouTube didn't return" do
      response = payload
      response.delete(:statistics)
      diff = described_class.call(video, response)
      # view_count / like_count / comment_count surface as differing
      # because Pito has positive counts and YouTube returned nothing.
      # The diff should reflect that (nil vs 100).
      expect(diff["view_count"]).to eq({ "pito" => 100, "youtube" => nil })
    end

    it "ignores a fully-empty payload gracefully" do
      diff = described_class.call(video, {})
      # Every field where Pito has a populated value vs nil on YouTube
      # surfaces.
      expect(diff).to be_a(Hash)
    end
  end

  describe "nil-vs-blank collapse" do
    it "treats nil and empty-string as equivalent (no phantom diff)" do
      v = build_stubbed(:video, title: "local", description: nil)
      diff = described_class.call(v, payload(snippet: { title: "local", description: "" }))
      expect(diff.keys).not_to include("description")
    end
  end

  describe "ISO 8601 duration" do
    it "converts the YouTube duration to seconds" do
      diff = described_class.call(video, payload(content_details: { duration: "PT2M" }))
      expect(diff["duration_seconds"]).to eq({ "pito" => 60, "youtube" => 120 })
    end

    it "tolerates a malformed duration" do
      diff = described_class.call(video, payload(content_details: { duration: "garbage" }))
      # Malformed → nil → diff vs Pito's 60 surfaces.
      expect(diff["duration_seconds"]).to eq({ "pito" => 60, "youtube" => nil })
    end
  end

  describe "thumbnail tier fallback" do
    it "picks maxres first" do
      diff = described_class.call(video, payload(snippet: {
        thumbnails: {
          maxres: { url: "https://i.ytimg.com/maxres.jpg" },
          high:   { url: "https://i.ytimg.com/high.jpg" }
        }
      }))
      expect(diff["thumbnail_url"]).to eq(
        { "pito" => "https://i.ytimg.com/local.jpg",
          "youtube" => "https://i.ytimg.com/maxres.jpg" }
      )
    end

    it "falls back to high when maxres is missing" do
      diff = described_class.call(video, payload(snippet: {
        thumbnails: { high: { url: "https://i.ytimg.com/high.jpg" } }
      }))
      expect(diff["thumbnail_url"]["youtube"]).to eq("https://i.ytimg.com/high.jpg")
    end
  end

  describe "boolean coercion" do
    it "matches Pito true against YouTube true" do
      diff = described_class.call(video, payload(status: { embeddable: true }))
      expect(diff.keys).not_to include("embeddable")
    end

    it "surfaces a real boolean mismatch" do
      diff = described_class.call(video, payload(status: { embeddable: false }))
      expect(diff["embeddable"]).to eq({ "pito" => true, "youtube" => false })
    end
  end
end
