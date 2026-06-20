# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Video::DetailComponent do
  let(:channel) { create(:channel) }
  let(:video) do
    create(:video,
           channel:          channel,
           title:            "My Awesome Let's Play",
           description:      "A test description.",
           tags:             %w[gaming rpg],
           duration_seconds: 3723,
           privacy_status:   :public)
  end

  describe "title" do
    it "renders the video title" do
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("My Awesome Let's Play")
    end
  end

  describe "category" do
    it "renders the category when present" do
      video_with_category = create(:video, channel: channel, category_id: "20")
      allow(video_with_category).to receive(:category_name).and_return("Gaming")
      node = render_inline(described_class.new(video: video_with_category))
      expect(node.text).to include("Gaming")
    end
  end

  describe "duration" do
    it "formats seconds as M:SS" do
      v = create(:video, channel: channel, duration_seconds: 185)
      node = render_inline(described_class.new(video: v))
      expect(node.text).to include("3:05")
    end

    it "formats seconds as H:MM:SS when >= 1 hour" do
      v = create(:video, channel: channel, duration_seconds: 3723)
      node = render_inline(described_class.new(video: v))
      expect(node.text).to include("1:02:03")
    end

    it "omits the duration row when duration_seconds is nil" do
      v = create(:video, channel: channel, duration_seconds: nil)
      node = render_inline(described_class.new(video: v))
      expect(node.text).not_to include(I18n.t("pito.video.detail.duration"))
    end
  end

  describe "tags" do
    it "renders tags joined by comma" do
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("gaming")
      expect(node.text).to include("rpg")
    end

    it "omits the tags row when tags array is empty" do
      v = create(:video, channel: channel, tags: [])
      node = render_inline(described_class.new(video: v))
      expect(node.text).not_to include(I18n.t("pito.video.detail.tags"))
    end
  end

  describe "description" do
    it "renders the description when present" do
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("A test description.")
    end

    it "omits the description row when description is blank" do
      v = create(:video, channel: channel, description: nil)
      node = render_inline(described_class.new(video: v))
      expect(node.text).not_to include(I18n.t("pito.video.detail.description"))
    end
  end

  describe "privacy" do
    it "renders the privacy label" do
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("Public")
    end
  end

  describe "stat counts" do
    it "renders — for nil view_count" do
      allow(video).to receive(:view_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("—")
    end

    it "renders the count when present" do
      allow(video).to receive(:view_count).and_return(42_000)
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("42000")
    end

    it "renders — for nil like_count" do
      allow(video).to receive(:like_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      # The stats row is always rendered, nil → "—"
      expect(node.text).to include("—")
    end

    it "renders — for nil comment_count" do
      allow(video).to receive(:comment_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("—")
    end
  end

  describe "thumbnail" do
    context "when no thumbnail is attached" do
      it "renders the no_thumbnail placeholder" do
        node = render_inline(described_class.new(video: video))
        expect(node.text).to include(I18n.t("pito.video.detail.no_thumbnail"))
      end
    end
  end

  describe "KV table (right column, before the description)" do
    it "renders the grid KV table in the right column" do
      node = render_inline(described_class.new(video: video))
      expect(node.css(".pito-video-detail__left div.grid.grid-cols-\\[max-content_1fr\\]")).to be_empty
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid).not_to be_nil
    end

    it "renders Title as the first kv row inside the table" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text).to include(I18n.t("pito.video.detail.title"))
      expect(grid.text).to include("My Awesome Let's Play")
    end

    it "renders the Title row before the ID row in source order" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      text = grid.text
      title_pos = text.index(I18n.t("pito.video.detail.title"))
      id_pos    = text.index(I18n.t("pito.video.detail.id"))
      expect(title_pos).to be < id_pos
    end

    it "renders the kv-table before the description in source order" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      html  = right.inner_html
      grid_pos = html.index("grid-cols-[max-content_1fr]")
      desc_pos = html.index("pito-video-detail__description")
      expect(grid_pos).to be < desc_pos
    end

    it "renders a hairline between the KV table and the description" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      expect(right.css("div.pito-detail-hairline").first).not_to be_nil
    end

    it "renders the Description label and body below the table" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      expect(right.text).to include(I18n.t("pito.video.detail.description"))
      expect(right.css(".pito-video-detail__description").first).not_to be_nil
    end
  end

  describe "ID and YouTube ID rows" do
    it "renders the internal db id, #-prefixed" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text).to include(I18n.t("pito.video.detail.id"))
      expect(grid.text).to include("##{video.id}")
    end

    it "renders the YouTube id from youtube_video_id" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text).to include(I18n.t("pito.video.detail.youtube_id"))
      expect(grid.text).to include(video.youtube_video_id)
    end
  end

  describe "right column" do
    it "renders the title in the right column" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      expect(right).not_to be_nil
      expect(right.text).to include("My Awesome Let's Play")
    end

    it "renders a Description label above the description body" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      expect(right.text).to include("Description")
      expect(right.text).to include("A test description.")
    end
  end

  describe "stats (one row)" do
    it "renders the V/L/C abbreviated stats on one line with · separators" do
      node  = render_inline(described_class.new(video: video))
      stats = node.css(".pito-video-detail__stats").first
      expect(stats).not_to be_nil
      expect(stats.text).to include("·")
      expect(stats.text).to include(I18n.t("pito.video.detail.views_abbr"))
      expect(stats.text).to include(I18n.t("pito.video.detail.likes_abbr"))
      expect(stats.text).to include(I18n.t("pito.video.detail.comments_abbr"))
    end

    it "uses the V views / L likes / C comms convention" do
      expect(I18n.t("pito.video.detail.views_abbr")).to eq("V")
      expect(I18n.t("pito.video.detail.likes_abbr")).to eq("L")
      expect(I18n.t("pito.video.detail.comments_abbr")).to eq("C")
    end
  end

  describe "stats legend" do
    it "renders the V/L/C legend line below the stats" do
      node   = render_inline(described_class.new(video: video))
      legend = node.css(".pito-video-detail__legend").first
      expect(legend).not_to be_nil
      expect(legend.text).to eq(Pito::Copy.render("pito.copy.videos.stats_legend"))
      expect(legend.text).to eq("V views, L likes, C comms")
    end
  end

  describe "rendering with nil stats" do
    it "does not raise when all stat counts are nil" do
      allow(video).to receive(:view_count).and_return(nil)
      allow(video).to receive(:like_count).and_return(nil)
      allow(video).to receive(:comment_count).and_return(nil)
      expect { render_inline(described_class.new(video: video)) }.not_to raise_error
    end
  end

  describe "Shinies block (left column, after the legend)" do
    context "when the video has achievements" do
      # views lane: multiple thresholds — only the max (1K) should render.
      let!(:views_small) do
        create(:achievement, achievable: video, metric: "views", threshold: 1,
                             unlocked_at: 4.weeks.ago)
      end
      let!(:views_max) do
        create(:achievement, achievable: video, metric: "views", threshold: 1_000,
                             unlocked_at: 1.week.ago)
      end
      # likes lane: single threshold (100) — the max and only badge for this metric.
      let!(:likes_max) do
        create(:achievement, achievable: video, metric: "likes", threshold: 100,
                             unlocked_at: 1.day.ago)
      end

      it "renders the Shinies heading in the left column" do
        node = render_inline(described_class.new(video: video))
        left = node.css(".pito-video-detail__left").first
        expect(left.text).to include("Shinies")
      end

      it "renders the Shinies heading element" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-video-detail__shinies-heading").first).not_to be_nil
      end

      it "renders exactly one badge per metric (2 total — views and likes)" do
        node   = render_inline(described_class.new(video: video))
        badges = node.css(".pito-video-detail__left .pito-achievement-badge")
        expect(badges.length).to eq(2)
      end

      it "shows the max-threshold badge for views (1K Views, not the lower threshold)" do
        node  = render_inline(described_class.new(video: video))
        texts = node.css(".pito-video-detail__left .pito-achievement-badge").map(&:text)
        expect(texts.any? { |t| t.include?("1K") && t.include?("Views") }).to be true
      end

      it "shows the max-threshold badge for likes (100 Likes)" do
        node  = render_inline(described_class.new(video: video))
        texts = node.css(".pito-video-detail__left .pito-achievement-badge").map(&:text)
        expect(texts.any? { |t| t.include?("100") && t.include?("Likes") }).to be true
      end

      it "renders badges ordered by recency of their lane — likes (1 day ago) before views (1 week ago)" do
        node   = render_inline(described_class.new(video: video))
        badges = node.css(".pito-video-detail__left .pito-achievement-badge")
        texts  = badges.map(&:text)
        likes_idx = texts.index { |t| t.include?("Likes") }
        views_idx = texts.index { |t| t.include?("Views") }
        expect(likes_idx).not_to be_nil
        expect(views_idx).not_to be_nil
        expect(likes_idx).to be < views_idx
      end

      it "renders a hairline before the Shinies heading" do
        node = render_inline(described_class.new(video: video))
        left = node.css(".pito-video-detail__left").first
        # The shinies block hairline is the second h-px hairline in the left column
        hairlines = left.css("div.h-px")
        expect(hairlines.length).to be >= 2
      end
    end

    context "when the video has no achievements" do
      it "renders no Shinies heading" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-video-detail__shinies-heading")).to be_empty
      end

      it "renders no achievement badges" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-achievement-badge")).to be_empty
      end
    end
  end
end
