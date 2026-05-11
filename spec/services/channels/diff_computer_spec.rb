require "rails_helper"

# Phase 7.5 §11i — Channels::DiffComputer.
#
# The pure-function comparator that turns a Channel + a normalized
# YouTube payload into a `{ field => { pito:, youtube: } }` hash of
# differing fields. Tests cover the whitelist, normalization rules
# (whitespace, nil-vs-blank), order-insensitive comparisons for
# keywords + links, and the CDN-rotation filter for asset URLs.
RSpec.describe Channels::DiffComputer, type: :service do
  # Helper — build a channel with the local-side values + a YouTube
  # payload with the same default values. Tests override either side
  # to surface a diff.
  let(:base_attrs) do
    {
      title: "Local Title",
      handle: "@local",
      description: "Local description",
      country: "US",
      default_language: "en",
      keywords: "tag1 tag2 tag3",
      banner_url: "https://yt3.ggpht.com/abc/banner.jpg?sz=320",
      avatar_url: "https://yt3.ggpht.com/abc/avatar.jpg",
      watermark_url: nil,
      watermark_timing: nil,
      watermark_offset_ms: nil,
      links: [
        { "title" => "site",   "url" => "https://example.com" },
        { "title" => "github", "url" => "https://github.com/u" }
      ]
    }
  end
  let(:channel) { create(:channel, **base_attrs) }

  let(:identical_payload) do
    base_attrs.merge(
      subscriber_count: 100, view_count: 1_000, video_count: 10
    )
  end

  describe "happy path" do
    it "returns {} when every whitelisted field matches" do
      expect(described_class.call(channel, identical_payload)).to eq({})
    end

    it "returns a single field when only title differs" do
      payload = identical_payload.merge(title: "Remote Title")
      diff = described_class.call(channel, payload)
      expect(diff.keys).to eq(%w[title])
      expect(diff["title"]).to eq({ "pito" => "Local Title", "youtube" => "Remote Title" })
    end

    it "returns each differing field when many differ" do
      payload = identical_payload.merge(title: "Remote", description: "Remote desc",
                                         country: "GB")
      diff = described_class.call(channel, payload)
      expect(diff.keys).to match_array(%w[title description country])
    end

    it "accepts String-keyed payloads (not just Symbol-keyed)" do
      payload = identical_payload.transform_keys(&:to_s).merge("title" => "Remote")
      diff = described_class.call(channel, payload)
      expect(diff.keys).to eq(%w[title])
    end

    it "accepts a nil payload as 'every field is nil'" do
      # A channel with all values set diffs against a totally empty
      # response (the YouTube row was deleted / inaccessible).
      diff = described_class.call(channel, nil)
      # `title`, `handle`, etc. all differ because Pito has values
      # and YouTube has nil.
      %w[title handle description country default_language keywords avatar_url banner_url].each do |field|
        expect(diff).to have_key(field)
      end
    end

    it "exposes the .new(...).call instance API in addition to .call" do
      diff = described_class.new(channel, identical_payload).call
      expect(diff).to eq({})
    end
  end

  describe "sad path — statistics are display-only" do
    it "never returns a diff for subscriber_count / view_count / video_count" do
      payload = identical_payload.merge(
        subscriber_count: 999_999,
        view_count: 999_999_999,
        video_count: 999_999
      )
      expect(described_class.call(channel, payload)).to eq({})
    end
  end

  describe "sad path — nil / empty equivalence" do
    let(:empty_channel) do
      create(:channel,
             title: nil, handle: nil, description: nil, country: nil,
             default_language: nil, keywords: nil, links: [],
             banner_url: nil, avatar_url: nil, watermark_url: nil,
             watermark_timing: nil, watermark_offset_ms: nil)
    end

    it "treats nil pito-side vs '' youtube-side as no diff" do
      payload = { title: "", description: "", country: "" }
      diff = described_class.call(empty_channel, payload)
      expect(diff).to eq({})
    end

    it "treats nil pito-side vs nil youtube-side as no diff" do
      diff = described_class.call(empty_channel, {})
      expect(diff).to eq({})
    end

    it "treats [] pito-side vs missing youtube-side as no diff for links" do
      payload = {} # no :links key at all
      diff = described_class.call(empty_channel, payload)
      expect(diff).not_to have_key("links")
    end

    it "treats whitespace-only description as nil" do
      whitespace_channel = create(:channel, description: "   \t\n  ")
      payload = identical_payload.dup
      payload.delete(:description)
      diff = described_class.call(whitespace_channel, payload)
      expect(diff).not_to have_key("description")
    end
  end

  describe "edge path — keywords / links order-insensitivity" do
    it "keywords reordered → no diff" do
      payload = identical_payload.merge(keywords: "tag3 tag2 tag1")
      expect(described_class.call(channel, payload)).to eq({})
    end

    it "keywords as Array vs space-separated String → no diff" do
      payload = identical_payload.merge(keywords: %w[tag2 tag1 tag3])
      expect(described_class.call(channel, payload)).to eq({})
    end

    it "keywords with extra whitespace collapsed → no diff" do
      payload = identical_payload.merge(keywords: "  tag1   tag2  tag3 ")
      expect(described_class.call(channel, payload)).to eq({})
    end

    it "keywords set changes → diff" do
      payload = identical_payload.merge(keywords: "tag1 tag2 tag4")
      diff = described_class.call(channel, payload)
      expect(diff.keys).to eq(%w[keywords])
    end

    it "links reordered → no diff" do
      payload = identical_payload.merge(links: [
        { "title" => "github", "url" => "https://github.com/u" },
        { "title" => "site",   "url" => "https://example.com" }
      ])
      expect(described_class.call(channel, payload)).to eq({})
    end

    it "links with symbol keys → still matches String-keyed local" do
      payload = identical_payload.merge(links: [
        { title: "site",   url: "https://example.com" },
        { title: "github", url: "https://github.com/u" }
      ])
      expect(described_class.call(channel, payload)).to eq({})
    end

    it "links membership changes → diff" do
      payload = identical_payload.merge(links: [
        { "title" => "site", "url" => "https://example.com" }
      ])
      diff = described_class.call(channel, payload)
      expect(diff.keys).to eq(%w[links])
    end
  end

  describe "edge path — whitespace normalization (Q-WHITESPACE)" do
    it "treats 'hello world' vs 'hello  world' (double space) as equal" do
      ws_channel = create(:channel, description: "hello world")
      payload = identical_payload.merge(description: "hello  world")
      diff = described_class.call(ws_channel, payload)
      expect(diff).not_to have_key("description")
    end

    it "treats 'hello' vs '  hello  ' (trim) as equal" do
      ws_channel = create(:channel, description: "hello")
      payload = identical_payload.merge(description: "  hello  ")
      diff = described_class.call(ws_channel, payload)
      expect(diff).not_to have_key("description")
    end

    it "treats real internal-content change as a diff" do
      diff = described_class.call(channel, identical_payload.merge(description: "Different content"))
      expect(diff.keys).to eq(%w[description])
    end
  end

  describe "edge path — CDN URL rotation filter (Q-CDN)" do
    it "banner_url with rotated query string only → no diff" do
      payload = identical_payload.merge(
        banner_url: "https://yt3.ggpht.com/abc/banner.jpg?sz=640&ts=xyz"
      )
      diff = described_class.call(channel, payload)
      expect(diff).not_to have_key("banner_url")
    end

    it "banner_url with rotated CDN host only → no diff" do
      payload = identical_payload.merge(
        banner_url: "https://yt4.ggpht.com/abc/banner.jpg?sz=320"
      )
      diff = described_class.call(channel, payload)
      expect(diff).not_to have_key("banner_url")
    end

    it "banner_url with changed path → diff" do
      payload = identical_payload.merge(
        banner_url: "https://yt3.ggpht.com/xyz/banner.jpg?sz=320"
      )
      diff = described_class.call(channel, payload)
      expect(diff.keys).to include("banner_url")
    end

    it "avatar_url rotation behaves the same" do
      payload = identical_payload.merge(
        avatar_url: "https://yt4.ggpht.com/abc/avatar.jpg?sz=640"
      )
      diff = described_class.call(channel, payload)
      expect(diff).not_to have_key("avatar_url")
    end

    it "watermark_url rotation behaves the same" do
      wm_channel = create(:channel, watermark_url: "https://yt3.ggpht.com/wm/seal.png?v=1")
      payload = identical_payload.merge(
        watermark_url: "https://yt4.ggpht.com/wm/seal.png?v=2"
      )
      diff = described_class.call(wm_channel, payload)
      expect(diff).not_to have_key("watermark_url")
    end
  end

  describe "flaw path — defensive against malformed payloads" do
    it "missing keys in payload collapse to nil, do not raise" do
      payload = { title: "Different" } # description, country, etc. omitted
      expect {
        described_class.call(channel, payload)
      }.not_to raise_error
    end

    it "payload with unrecognized keys is ignored silently" do
      payload = identical_payload.merge(
        experimental_field: "some-future-feature",
        another_extra: 42
      )
      diff = described_class.call(channel, payload)
      expect(diff.keys).not_to include("experimental_field", "another_extra")
    end

    it "watermark_offset_ms compares as integer (string vs int both ok)" do
      ws_channel = create(:channel, watermark_offset_ms: 1500)
      payload = identical_payload.merge(watermark_offset_ms: "1500")
      diff = described_class.call(ws_channel, payload)
      expect(diff).not_to have_key("watermark_offset_ms")
    end

    it "watermark_offset_ms diff surfaces when integers differ" do
      ws_channel = create(:channel, watermark_offset_ms: 1500)
      payload = identical_payload.merge(watermark_offset_ms: 2500)
      diff = described_class.call(ws_channel, payload)
      expect(diff.keys).to include("watermark_offset_ms")
    end
  end

  describe "stored shape" do
    it "stores values as plain Ruby (jsonb-safe) — Time → ISO-string fallback" do
      payload = identical_payload.merge(title: "Remote")
      diff = described_class.call(channel, payload)
      expect(diff["title"]["pito"]).to be_a(String)
      expect(diff["title"]["youtube"]).to be_a(String)
    end
  end
end
