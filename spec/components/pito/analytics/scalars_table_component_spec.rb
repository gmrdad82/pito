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

  describe "grid layout" do
    it "renders the outer grid with grid-cols-6" do
      node = render_for(result)
      expect(node.css("div.pito-analytics-scalars.grid-cols-6")).not_to be_empty
    end

    it "renders row 1 cells (views, watch hours) with col-span-3" do
      node = render_for(result)
      texts = node.css("div.col-span-3").map(&:text)
      expect(texts.any? { |t| t.include?("Views") }).to be true
      expect(texts.any? { |t| t.include?("Watch hours") }).to be true
    end

    it "renders row 2 cells (avg view duration, avg viewed %) with col-span-3" do
      node = render_for(result)
      texts = node.css("div.col-span-3").map(&:text)
      expect(texts.any? { |t| t.include?("Avg view duration") }).to be true
      expect(texts.any? { |t| t.include?("Avg viewed %") }).to be true
    end

    it "renders row 3 (subs net) as a col-span-3 cell (same column as Views)" do
      node = render_for(result)
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell).to be_present
      expect(node.css("div.col-span-6")).to be_empty
    end

    it "renders rows in the correct order: views, avg, subs, likes" do
      node = render_for(result)
      text = node.text
      views_pos    = text.index("Views")
      avg_pos      = text.index("Avg view duration")
      subs_pos     = text.index("Subs")
      likes_pos    = text.index("Likes")
      expect(views_pos).to be < avg_pos
      expect(avg_pos).to  be < subs_pos
      expect(subs_pos).to be < likes_pos
    end

    it "renders row 4 cells (likes, dislikes, comms) with col-span-2" do
      node = render_for(result)
      texts = node.css("div.col-span-2").map(&:text)
      expect(texts.any? { |t| t.include?("Likes") }).to be true
      expect(texts.any? { |t| t.include?("Dislikes") }).to be true
      expect(texts.any? { |t| t.include?("Comms") }).to be true
    end

    it "wraps every metric value in a tabular-nums span" do
      node = render_for(result)
      # 2 (row1) + 2 (row2) + 1 (row3 subs) + 3 (row4) = 8 value wrappers
      expect(node.css("span.tabular-nums").size).to eq(8)
    end
  end

  describe "subs net (row 3)" do
    it "shows +N green (--up) for a net gain" do
      # default: gained=20, lost=9 → net=11 → "+11"
      node = render_for(result)
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell.text).to include("+")
      expect(subs_cell.css("span.pito-trend-number--up")).not_to be_empty
    end

    it "shows -N red (--down) for a net loss" do
      node = render_for(result(subs_gained: { current: 5,  previous: 10 },
                               subs_lost:   { current: 20, previous: 4 }))
      # net = 5 - 20 = -15
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell.text).to include("-")
      expect(subs_cell.css("span.pito-trend-number--down")).not_to be_empty
    end

    it "shows — plain (no --up/--down) when net is zero" do
      node = render_for(result(subs_gained: { current: 5, previous: 3 },
                               subs_lost:   { current: 5, previous: 3 }))
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell.text).to include("—")
      expect(subs_cell.css("span.pito-trend-number--up")).to be_empty
      expect(subs_cell.css("span.pito-trend-number--down")).to be_empty
    end

    it "shows — plain (no --up/--down) when both subs_gained and subs_lost are nil" do
      node = render_for(result(subs_gained: { current: nil, previous: nil },
                               subs_lost:   { current: nil, previous: nil }))
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell.text).to include("—")
      expect(subs_cell.css("span.pito-trend-number--up")).to be_empty
      expect(subs_cell.css("span.pito-trend-number--down")).to be_empty
    end

    it "colours subs net by sign regardless of the comparable window" do
      # Even when the result is not comparable (lifetime), subs net shows sign colour.
      node = render_for(result(comparable: false))
      # default net = 20 - 9 = 11 → :up
      subs_cell = node.css("div.col-span-3").find { |d| d.text.include?("Subs") }
      expect(subs_cell.css("span.pito-trend-number--up")).not_to be_empty
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

    it "formats watch hours under 10 with a decimal + h suffix" do
      expect(render_for(result(watched_hours: { current: 8.5, previous: 7.0 })).text).to include("8.5h")
    end

    it "formats watch hours of 10+ compactly with an h suffix" do
      expect(render_for(result(watched_hours: { current: 12.5, previous: 10.0 })).text).to include("13h")
    end

    it "shows an em dash for a nil value" do
      node = render_for(result(views: { current: nil, previous: nil }))
      expect(node.text).to include("—")
    end
  end

  describe "polarity" do
    it "renders a numeric rise in a more-is-worse metric (dislikes) as down" do
      # dislikes current=4 > previous=2 → numeric :up, polarity false → visual :down
      node = render_for(result)
      down = node.css("span.pito-trend-number[data-trend='down']").map(&:text)
      expect(down).to include(Pito::Formatter::CompactCount.call(4))
    end
  end

  describe "lifetime (no baseline)" do
    it "renders the 7 non-subs metrics as neutral when not comparable" do
      node = render_for(result(comparable: false))
      # subs_net always uses comparable: true (sign-based colouring), so only
      # the 7 regular metrics (views, watched_hours, avg_view_duration,
      # avg_viewed_pct, likes, dislikes, comments) are forced neutral.
      expect(node.css("span.pito-trend-number[data-trend='neutral']").size).to eq(7)
    end

    it "does not produce up/down trends on the 7 comparable-gated metrics" do
      node = render_for(result(comparable: false))
      up_data_attrs   = node.css("span.pito-trend-number[data-trend='up']")
      down_data_attrs = node.css("span.pito-trend-number[data-trend='down']")
      # Only the subs-net cell can still be up/down (sign-based); all others must be absent
      expect(up_data_attrs.size + down_data_attrs.size).to eq(1) # just the subs net :up
    end
  end
end
