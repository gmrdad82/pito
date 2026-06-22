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

  def cell_containing(node, text)
    node.css("div.col-span-2, div.col-span-3").find { |d| d.text.include?(text) }
  end

  describe "grid layout" do
    it "renders the outer grid with grid-cols-6" do
      node = render_for(result)
      expect(node.css("div.pito-analytics-scalars.grid-cols-6")).not_to be_empty
    end

    it "renders row 1 cells (views, watched hours) with col-span-3" do
      node = render_for(result)
      texts = node.css("div.col-span-3").map(&:text)
      expect(texts.any? { |t| t.include?("Views") }).to be true
      expect(texts.any? { |t| t.include?("Watched hours") }).to be true
    end

    it "renders row 2 cells (avg view duration, avg viewed %) with col-span-3" do
      node = render_for(result)
      texts = node.css("div.col-span-3").map(&:text)
      expect(texts.any? { |t| t.include?("Avg view duration") }).to be true
      expect(texts.any? { |t| t.include?("Avg viewed %") }).to be true
    end

    it "renders subs & likes on row 3 and comms on its own row 4 (all col-span-3, no col-span-2/6)" do
      node = render_for(result)
      texts = node.css("div.col-span-3").map(&:text)
      expect(texts.any? { |t| t.include?("Subs") }).to be true
      expect(texts.any? { |t| t.include?("Likes") }).to be true
      expect(texts.any? { |t| t.include?("Comms") }).to be true
      # Comms keeps the 2-metric-column grid by sitting alone on its own row (no 3-across).
      expect(node.css("div.col-span-2")).to be_empty
      expect(node.css("div.col-span-6")).to be_empty
    end

    it "renders rows in the correct order: views, avg, subs, likes, comms" do
      node = render_for(result)
      text = node.text
      expect(text.index("Views")).to be < text.index("Avg view duration")
      expect(text.index("Avg view duration")).to be < text.index("Subs")
      expect(text.index("Subs")).to be < text.index("Likes")
      expect(text.index("Likes")).to be < text.index("Comms")
    end

    it "does not render a standalone Dislikes label row" do
      node = render_for(result)
      labels = node.css("span.text-fg-dim").map(&:text)
      expect(labels).not_to include("Dislikes")
    end

    it "wraps every metric value in a tabular-nums span" do
      node = render_for(result)
      # 2 (row1) + 2 (row2) + 3 (row3: subs, likes, comms) = 7 value wrappers
      expect(node.css("span.tabular-nums").size).to eq(7)
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

    it "does not render a separate Dislikes value cell" do
      node = render_for(result)
      # Only one metric cell carries thumbs icons (the merged likes cell).
      icon_cells = node.css("div.col-span-3").select { |d| d.at_css("svg") }
      expect(icon_cells.size).to eq(1)
    end

    it "shows an em dash when both likes and dislikes are nil" do
      node = render_for(result(likes:    { current: nil, previous: nil },
                               dislikes: { current: nil, previous: nil }))
      likes = cell_containing(node, "Likes")
      expect(likes.text).to include("—")
      expect(likes.at_css("svg")).to be_nil
    end
  end

  describe "comms cell" do
    it "renders the word label and a plain trend-coloured count" do
      node = render_for(result)
      comms = cell_containing(node, "Comms")
      expect(comms.text).to include("31")
      expect(comms.at_css("span.pito-trend-number")).to be_present
    end
  end

  describe "formatting" do
    it "formats counts compactly" do
      expect(render_for(result).text).to include("1.2K") # views
    end

    it "formats avg view duration as m:ss" do
      expect(render_for(result).text).to include("4:05") # 245s
    end

    it "formats avg viewed % as a rounded percentage" do
      expect(render_for(result).text).to include("38%")
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
      # Comparable-gated TrendNumberComponents: views, watched_hours,
      # avg_view_duration, avg_viewed_pct, comments = 5. The subs and likes cells
      # are always sign/side-coloured (custom shimmer spans), never neutral.
      expect(node.css("span.pito-trend-number[data-trend='neutral']").size).to eq(5)
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
