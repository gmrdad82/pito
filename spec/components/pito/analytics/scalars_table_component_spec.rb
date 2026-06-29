# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::ScalarsTableComponent, type: :component do
  def result(comparable: true, **overrides)
    metrics = {
      views:             { current: 1234, previous: 1000 },
      watched_hours:     { current: 12.5, previous: 10.0 },
      avg_view_duration: { current: 245,  previous: 200 },
      avg_viewed_pct:    { current: 38.2, previous: 40.0 },
      subs_gained:       { current: 20,   previous: 10 },
      subs_lost:         { current: 9,    previous: 4 },
      likes:             { current: 210,  previous: 180 },
      dislikes:          { current: 4,    previous: 2 },
      comments:          { current: 31,   previous: 30 }
    }.merge(overrides)
    Pito::Analytics::Scalars::Result.new(metrics: metrics, label: "28d", comparable: comparable)
  end

  def render_for(res)
    render_inline(described_class.new(result: res))
  end

  # Find the pair div that contains the given text (label or value).
  def cell_containing(node, text)
    node.css("div.pito-analytics-scalars__pair").find { |d| d.text.include?(text) }
  end

  describe "flex-wrap layout" do
    it "renders the outer container with the pito-analytics-scalars class" do
      node = render_for(result)
      expect(node.css("div.pito-analytics-scalars")).not_to be_empty
    end

    it "does not use the old grid-cols-6 / col-span-3 scheme" do
      node = render_for(result)
      expect(node.css("div.grid-cols-6")).to be_empty
      expect(node.css("div.col-span-3")).to be_empty
      expect(node.css("div.col-span-2")).to be_empty
    end

    it "renders exactly 5 __pair elements (one per metric: views/watched/avg_dur/subs/likes)" do
      node = render_for(result)
      expect(node.css("div.pito-analytics-scalars__pair").size).to eq(5)
    end

    it "gives every __pair a __label and a __value span so widths are uniform" do
      node = render_for(result)
      node.css("div.pito-analytics-scalars__pair").each do |pair|
        expect(pair.at_css("span.pito-analytics-scalars__label")).to be_present
        expect(pair.at_css("span.pito-analytics-scalars__value")).to be_present
      end
    end

    it "renders the labels for the 5 metrics (comments + avg viewed % removed)" do
      node = render_for(result)
      labels = node.css("span.pito-analytics-scalars__label").map(&:text)
      expect(labels).to include("Views", "Watched hours", "Average view duration", "Subs", "Likes")
      expect(labels).not_to include("Average percentage viewed", "Comments")
    end

    it "renders rows in the correct order: views, avg view duration, subs, likes" do
      node = render_for(result)
      text = node.text
      expect(text.index("Views")).to be < text.index("Average view duration")
      expect(text.index("Average view duration")).to be < text.index("Subs")
      expect(text.index("Subs")).to be < text.index("Likes")
    end

    it "does not render a standalone Dislikes label" do
      node = render_for(result)
      labels = node.css("span.pito-analytics-scalars__label").map(&:text)
      expect(labels).not_to include("Dislikes")
    end

    it "wraps every metric value in a tabular-nums __value span (5 total)" do
      node = render_for(result)
      expect(node.css("span.pito-analytics-scalars__value.tabular-nums").size).to eq(5)
    end
  end

  describe "subs cell (+gained/-lost)" do
    it "shows +gained green (--up) and -lost red (--down)" do
      # default: gained=20, lost=9 → "+20" / "-9"
      node = render_for(result)
      subs = cell_containing(node, "Subs")
      expect(subs.text).to include("+20")
      expect(subs.text).to include("-9")
      up   = subs.css("span.pito-trend-number--up")
      down = subs.css("span.pito-trend-number--down")
      expect(up.text).to include("+20")
      expect(down.text).to include("-9")
    end

    it "shows an em dash when both subs_gained and subs_lost are nil" do
      node = render_for(result(subs_gained: { current: nil, previous: nil },
                               subs_lost:   { current: nil, previous: nil }))
      subs = cell_containing(node, "Subs")
      expect(subs.text).to include("—")
      expect(subs.css("span.pito-trend-number--up")).to be_empty
      expect(subs.css("span.pito-trend-number--down")).to be_empty
    end

    it "colours the split regardless of the comparable window" do
      node = render_for(result(comparable: false))
      subs = cell_containing(node, "Subs")
      expect(subs.css("span.pito-trend-number--up")).not_to be_empty
      expect(subs.css("span.pito-trend-number--down")).not_to be_empty
    end

    it "synchronises both halves to ONE shimmer offset (pulse together, not adrift)" do
      node = render_for(result)
      subs = cell_containing(node, "Subs")
      up   = subs.at_css("span.pito-trend-number--up")
      down = subs.at_css("span.pito-trend-number--down")
      up_offset   = up["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      down_offset = down["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      expect(up_offset).not_to be_empty
      # Same single dN class on both halves → same animation-delay → in phase.
      expect(up_offset).to eq(down_offset)
    end

    it "separates the split with a spaced '/' so the values breathe" do
      node = render_for(result)
      subs = cell_containing(node, "Subs")
      sep  = subs.css("span.text-fg-dim").find { |s| s.text.include?("/") }
      expect(sep).to be_present
      expect(sep.text).to eq(" / ")
    end
  end

  describe "likes cell (<likes>👍/<dislikes>👎)" do
    it "shows likes + thumbs-up green and dislikes + thumbs-down red" do
      node = render_for(result)
      likes = cell_containing(node, "Likes")

      up   = likes.css("span.pito-trend-number--up")
      down = likes.css("span.pito-trend-number--down")
      expect(up.text).to include("210")
      expect(down.text).to include("4")

      expect(up.at_css("svg")["aria-label"]).to eq("Likes")
      expect(down.at_css("svg")["aria-label"]).to eq("Dislikes")
    end

    it "nests each icon INSIDE its trend-shimmer span so the icon shares the number's shimmer" do
      node = render_for(result)
      likes = cell_containing(node, "Likes")

      # The 👍 must be a descendant of the .pito-trend-number--up span (and 👎 of
      # --down): the CSS rule `.pito-trend-number--up .pito-icon` animates the
      # icon's colour on the same cadence, so number + icon shimmer as one unit.
      up_icon   = likes.at_css("span.pito-trend-number--up svg.pito-icon")
      down_icon = likes.at_css("span.pito-trend-number--down svg.pito-icon")
      expect(up_icon).to be_present
      expect(down_icon).to be_present
      expect(up_icon["aria-label"]).to eq("Likes")
      expect(down_icon["aria-label"]).to eq("Dislikes")
    end

    it "frame-locks each icon to its number by sharing the span's pito-shimmer-dN offset" do
      node  = render_for(result)
      likes = cell_containing(node, "Likes")
      up    = likes.at_css("span.pito-trend-number--up")
      down  = likes.at_css("span.pito-trend-number--down")

      # The shimmer offset (animation-delay stagger) lives on the trend-number
      # span; the icon is nested INSIDE it and inherits that delay via CSS
      # (`.pito-icon { animation-delay: inherit }`), so the icon never carries
      # its own offset class — it shares the number's exact phase.
      up_offset   = up["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      down_offset = down["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      expect(up_offset).not_to be_empty
      expect(down_offset).not_to be_empty

      up_icon   = up.at_css("svg.pito-icon")
      down_icon = down.at_css("svg.pito-icon")
      expect(up_icon["class"].to_s.split.grep(/\Apito-shimmer-d\d+\z/)).to be_empty
      expect(down_icon["class"].to_s.split.grep(/\Apito-shimmer-d\d+\z/)).to be_empty
    end

    it "does not render a separate Dislikes value cell" do
      node = render_for(result)
      # Only one metric pair carries thumbs icons (the merged likes cell).
      icon_pairs = node.css("div.pito-analytics-scalars__pair").select { |d| d.at_css("svg") }
      expect(icon_pairs.size).to eq(1)
    end

    it "synchronises the 👍 / 👎 halves to one shimmer offset and spaces the '/'" do
      node  = render_for(result)
      likes = cell_containing(node, "Likes")
      up    = likes.at_css("span.pito-trend-number--up")
      down  = likes.at_css("span.pito-trend-number--down")
      up_offset   = up["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      down_offset = down["class"].split.grep(/\Apito-shimmer-d\d+\z/)
      expect(up_offset).not_to be_empty
      expect(up_offset).to eq(down_offset)
      sep = likes.css("span.text-fg-dim").find { |s| s.text.include?("/") }
      expect(sep.text).to eq(" / ")
    end

    it "shows an em dash when both likes and dislikes are nil" do
      node = render_for(result(likes:    { current: nil, previous: nil },
                               dislikes: { current: nil, previous: nil }))
      likes = cell_containing(node, "Likes")
      expect(likes.text).to include("—")
      expect(likes.at_css("svg")).to be_nil
    end
  end

  describe "formatting" do
    it "formats counts compactly" do
      expect(render_for(result).text).to include("1.2K") # views
    end

    it "formats avg view duration as m:ss" do
      expect(render_for(result).text).to include("4:05") # 245s
    end

    it "formats watched hours under 10 with a decimal + h suffix" do
      expect(render_for(result(watched_hours: { current: 8.5, previous: 7.0 })).text).to include("8.5h")
    end

    it "formats watched hours of 10+ compactly with an h suffix" do
      expect(render_for(result(watched_hours: { current: 12.5, previous: 10.0 })).text).to include("13h")
    end

    it "shows an em dash for a nil value" do
      node = render_for(result(views: { current: nil, previous: nil }))
      expect(node.text).to include("—")
    end
  end

  describe "lifetime (no baseline)" do
    it "renders the comparable-gated metrics as neutral when not comparable" do
      node = render_for(result(comparable: false))
      # Comparable-gated TrendNumberComponents now: views, watched_hours,
      # avg_view_duration = 3 (avg_viewed_pct + comments removed from the glance).
      # The subs and likes cells are always sign/side-coloured, never neutral.
      expect(node.css("span.pito-trend-number[data-trend='neutral']").size).to eq(3)
    end

    it "still colours the subs and likes split cells when not comparable" do
      node = render_for(result(comparable: false))
      up   = node.css("span.pito-trend-number[data-trend='up']")
      down = node.css("span.pito-trend-number[data-trend='down']")
      # subs (+/-) and likes (👍/👎) each contribute one up and one down span.
      expect(up.size).to eq(2)
      expect(down.size).to eq(2)
    end
  end
end
