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

  describe "root layout" do
    it "carries flex-col (mobile-first single-column default)" do
      node = render_inline(described_class.new(video: video))
      root = node.css(".pito-video-detail").first
      expect(root["class"]).to include("flex-col")
    end

    it "carries md:flex-row (desktop two-column at the md: breakpoint)" do
      node = render_inline(described_class.new(video: video))
      root = node.css(".pito-video-detail").first
      expect(root["class"]).to include("md:flex-row")
    end

    it "carries md:items-start (aligns columns at the top on desktop)" do
      node = render_inline(described_class.new(video: video))
      root = node.css(".pito-video-detail").first
      expect(root["class"]).to include("md:items-start")
    end
  end

  # ── Mobile-only column divider (L6) ─────────────────────────────────────────
  # A hairline between the stacked thumbnail and kv-table columns on mobile
  # (<768px), hidden at md: and up where the two-column layout needs no divider.
  describe "mobile-only column divider" do
    it "renders a hairline divider between the columns" do
      node    = render_inline(described_class.new(video: video))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider).not_to be_nil
      expect(divider["class"]).to include("h-px")
    end

    it "is hidden on desktop (carries md:hidden)" do
      node    = render_inline(described_class.new(video: video))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider["class"]).to include("md:hidden")
    end
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

  describe "last sync at row (C1)" do
    it "renders the last-sync stamp" do
      video.update!(last_synced_at: Time.zone.local(2026, 6, 26, 14, 30))
      text = render_inline(described_class.new(video: video)).text
      expect(text).to include("Last sync at").and include("26-06-2026 14:30")
    end

    it "renders an em-dash when never synced" do
      video.update!(last_synced_at: nil)
      expect(render_inline(described_class.new(video: video)).text).to include("Last sync at")
    end

    it "renders the Last sync at row directly after the visibility (privacy) row" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      text = grid.text
      privacy_pos   = text.index(I18n.t("pito.video.detail.privacy"))
      last_sync_pos = text.index(I18n.t("pito.video.detail.last_sync_at"))
      expect(privacy_pos).not_to be_nil
      expect(privacy_pos).to be < last_sync_pos
    end
  end

  describe "tags" do
    it "renders tags joined by comma" do
      node = render_inline(described_class.new(video: video))
      expect(node.text).to include("gaming")
      expect(node.text).to include("rpg")
    end

    it "omits the tags section when tags array is empty" do
      v = create(:video, channel: channel, tags: [])
      node = render_inline(described_class.new(video: v))
      expect(node.text).not_to include(I18n.t("pito.video.detail.tags"))
    end

    it "renders tags as a section below the description (not a kv-row)" do
      node = render_inline(described_class.new(video: video))
      grid = node.css(".pito-video-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      # Tags are NOT in the kv-table grid anymore…
      expect(grid.text).not_to include(I18n.t("pito.video.detail.tags"))
      # …they render in their own labelled body below the description.
      right = node.css(".pito-video-detail__right").first
      expect(right.css(".pito-video-detail__tags").first).not_to be_nil
      html = right.inner_html
      expect(html.index("pito-video-detail__description")).to be < html.index("pito-video-detail__tags")
    end

    it "separates the tags section with its own hairline" do
      node  = render_inline(described_class.new(video: video))
      right = node.css(".pito-video-detail__right").first
      # kv→description hairline + description→tags hairline = two detail hairlines.
      expect(right.css("div.pito-detail-hairline").length).to eq(2)
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

  # U6 — the scheduled go-live is split out of the Visibility scope: Visibility
  # shows the bare "Scheduled" scope (not "Scheduled for <time>"), and the time
  # lives in its own "Publish at" field matching the list column name.
  describe "publish at (U6)" do
    # Far-future so it is always a scheduled (future publish_at) vid regardless of
    # test-clock, and SyncStamp formats the given instant independent of "now".
    let(:go_live)   { Time.zone.local(2099, 3, 1, 13, 0) }
    let(:scheduled) { create(:video, :scheduled, channel: channel, title: "Sched", publish_at: go_live) }

    it "shows Visibility as the bare 'Scheduled' scope (no welded time)" do
      text = render_inline(described_class.new(video: scheduled)).text
      expect(text).to include("Scheduled")
      expect(text).not_to include("Scheduled for")
    end

    it "renders a 'Publish at' field with the bare timestamp" do
      text = render_inline(described_class.new(video: scheduled)).text
      expect(text).to include(I18n.t("pito.video.detail.publish_at"))
      expect(text).to include(Pito::Formatter::SyncStamp.call(go_live))
    end

    it "omits the 'Publish at' field for a non-scheduled vid" do
      text = render_inline(described_class.new(video: video)).text
      expect(text).not_to include(I18n.t("pito.video.detail.publish_at"))
    end

    it "omits the 'Publish at' field for a stale past publish_at (already live)" do
      stale = create(:video, :scheduled, channel: channel, title: "Stale", publish_at: 2.days.ago)
      text  = render_inline(described_class.new(video: stale)).text
      expect(text).not_to include(I18n.t("pito.video.detail.publish_at"))
    end
  end

  describe "stat counts" do
    it "renders '0 Views' for nil view_count" do
      allow(video).to receive(:view_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      stats = node.at_css(".pito-video-detail__stats")
      expect(stats.text).to include("0").and include("Views")
    end

    it "renders the CompactCount for a present view_count" do
      allow(video).to receive(:view_count).and_return(42_000)
      node = render_inline(described_class.new(video: video))
      stats = node.at_css(".pito-video-detail__stats")
      expect(stats.text).to include("42K")
    end

    it "renders '0' + thumbs-up icon for nil like_count" do
      allow(video).to receive(:like_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      stats = node.at_css(".pito-video-detail__stats")
      expect(stats.text).to include("0")
      expect(stats.css("svg").map { |s| s["aria-label"] }).to include("Likes")
    end

    it "renders '0' + message-square icon for nil comment_count" do
      allow(video).to receive(:comment_count).and_return(nil)
      node = render_inline(described_class.new(video: video))
      stats = node.at_css(".pito-video-detail__stats")
      expect(stats.text).to include("0")
      expect(stats.css("svg").map { |s| s["aria-label"] }).to include("Comments")
    end
  end

  describe "thumbnail" do
    context "when no thumbnail is attached" do
      it "renders the click-to-sync image placeholder (rect) in the thumbnail box (item 22)" do
        node     = render_inline(described_class.new(video: video))
        fallback = node.at_css(".pito-video-detail__thumbnail .pito-image-fallback")
        expect(fallback).to be_present
        expect(fallback.at_css(".pito-image-fallback--circle")).to be_nil
        expect(fallback["data-pito--chat-prefill-text-value"]).to eq("sync vid ##{video.id}")
        expect(fallback["data-pito--chat-prefill-submit-value"]).to eq("true")
      end
    end
  end

  describe "intro timestamp inline flow" do
    let(:node_with_intro) { render_inline(described_class.new(video: video, intro: "Test intro line")) }

    it "intro div is inline-flow (not flex) so the timestamp leads the copy and long copy wraps beneath it" do
      intro = node_with_intro.css(".pito-video-detail__intro").first
      expect(intro["class"]).not_to include("flex")
    end

    it "timestamp slot is a direct child of the intro flex container (no block boundary)" do
      slot = node_with_intro.css(".pito-video-detail__intro > [data-pito-ts-slot]").first
      expect(slot).not_to be_nil
    end

    it "intro copy text is present inside the intro flex container" do
      intro = node_with_intro.css(".pito-video-detail__intro").first
      expect(intro.text).to include("Test intro line")
    end

    it "renders an html_safe intro (subject-shimmer span) raw, not escaped" do
      html  = Pito::Copy.render_html("pito.copy.video.detail_intro", { title: video.title }, shimmer: [ :title ])
      node  = render_inline(described_class.new(video: video, intro: html))
      intro = node.css(".pito-video-detail__intro").first
      expect(intro.css("span.pito-subject-shimmer").map(&:text)).to include(video.title)
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

    it "wires the #id token to prefill + auto-submit `show video #id`" do
      node    = render_inline(described_class.new(video: video))
      id_text = "##{video.id}"
      span    = node.css("span.pito-action-shimmer").find { |s| s.text == id_text }
      expect(span).to be_present
      expect(span["data-controller"]).to eq("pito--chat-prefill")
      expect(span["data-action"]).to eq("click->pito--chat-prefill#fill")
      expect(span["data-pito--chat-prefill-text-value"]).to eq("show video ##{video.id}")
      expect(span["data-pito--chat-prefill-submit-value"]).to eq("true")
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
    it "renders the Views word + likes/comments icons on one line with · separators" do
      node  = render_inline(described_class.new(video: video))
      stats = node.css(".pito-video-detail__stats").first
      expect(stats).not_to be_nil
      expect(stats.text).to include("·")
      expect(stats.text).to include("Views")
    end

    it "renders likes as thumbs-up and comments as message-square icons (no word labels)" do
      node  = render_inline(described_class.new(video: video))
      stats = node.css(".pito-video-detail__stats").first
      labels = stats.css("svg").map { |s| s["aria-label"] }
      expect(labels).to include("Likes").and include("Comments")
      # Icon metrics show no visible word label.
      counters_text = stats.css(".pito-stats-counters").text
      expect(counters_text).not_to include("Likes")
      expect(counters_text).not_to include("Comments")
    end

    it "does not bold the Stats heading (J19 — normal weight)" do
      node    = render_inline(described_class.new(video: video))
      heading = node.css(".pito-video-detail__stats-heading").first
      expect(heading["class"]).not_to include("font-bold")
    end
  end

  describe "stats legend" do
    it "does not render a per-video stats legend line (removed in refactor)" do
      node = render_inline(described_class.new(video: video))
      expect(node.css(".pito-video-detail__legend")).to be_empty
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
        badges = node.css(".pito-video-detail__left .pito-shiny")
        expect(badges.length).to eq(2)
      end

      it "shows the max-threshold badge for views (1K Views, not the lower threshold)" do
        node  = render_inline(described_class.new(video: video))
        texts = node.css(".pito-video-detail__left .pito-shiny").map(&:text)
        expect(texts.any? { |t| t.include?("1K") && t.include?("Views") }).to be true
      end

      it "shows the max-threshold badge for likes (100 Likes)" do
        node  = render_inline(described_class.new(video: video))
        texts = node.css(".pito-video-detail__left .pito-shiny").map(&:text)
        expect(texts.any? { |t| t.include?("100") && t.include?("Likes") }).to be true
      end

      it "renders badges ordered by recency of their lane — likes (1 day ago) before views (1 week ago)" do
        node   = render_inline(described_class.new(video: video))
        badges = node.css(".pito-video-detail__left .pito-shiny")
        texts  = badges.map(&:text)
        # anchor on threshold values (100 Likes vs 1K Views) which are unambiguous
        likes_idx = texts.index { |t| t.include?("100") }
        views_idx = texts.index { |t| t.include?("1K") }
        expect(likes_idx).not_to be_nil
        expect(views_idx).not_to be_nil
        expect(likes_idx).to be < views_idx
      end

      it "renders the thumbnail–stats hairline in the left column" do
        node = render_inline(described_class.new(video: video))
        left = node.css(".pito-video-detail__left").first
        # One hairline between the thumbnail and the stats block (shinies hairline removed)
        hairlines = left.css("div.h-px")
        expect(hairlines.length).to be >= 1
      end

      it "does not bold the Shinies heading (J19 — normal weight)" do
        node    = render_inline(described_class.new(video: video))
        heading = node.css(".pito-video-detail__shinies-heading").first
        expect(heading["class"]).not_to include("font-bold")
      end

      it "renders detail-card badges in compact form — no unlock date span (J11/J18)" do
        node   = render_inline(described_class.new(video: video))
        badges = node.css(".pito-video-detail__shinies .pito-shiny")
        badges.each do |badge|
          expect(badge.css(".pito-shiny__date")).to be_empty
        end
      end

      it "lays out badges in a left-aligned flex-wrap container" do
        node    = render_inline(described_class.new(video: video))
        shinies = node.css(".pito-video-detail__shinies").first
        expect(shinies["class"]).to include("pito-detail-card__shinies")
        expect(shinies["class"]).not_to include("justify-center")
      end

      it "does not render a Shinies legend (removed in the metric-display overhaul)" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-video-detail__shinies-legend")).to be_empty
      end
    end

    context "when the video has no achievements" do
      it "renders no Shinies heading" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-video-detail__shinies-heading")).to be_empty
      end

      it "renders no achievement badges" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-shiny")).to be_empty
      end

      it "renders no Shinies legend" do
        node = render_inline(described_class.new(video: video))
        expect(node.css(".pito-video-detail__shinies-legend")).to be_empty
      end
    end
  end
end
