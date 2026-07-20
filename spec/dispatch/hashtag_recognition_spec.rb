# frozen_string_literal: true

require "rails_helper"

# Phase D — hashtag recognition. The #handle/action/rest parse is pure; the
# target→handler resolution is DB-bound (the #handle points to a live event), so
# here we assert the parse + the per-target ACTION GATING (which actions each
# follow-up target accepts — the canonical reply matrix). No DB.
RSpec.describe "Dispatch — hashtag recognition + action gating", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  describe "parse: #handle action rest" do
    {
      "#a1b2 show 5"            => { handle: "a1b2", action: "show", rest: "5" },
      "#h sort by views desc"   => { handle: "h",    action: "sort", rest: "by views desc" },
      "#h sync"                 => { handle: "h",    action: "sync", rest: "" },
      "#h analyze"              => { handle: "h",    action: "analyze", rest: "" },
      "#a1b2 with views, likes" => { handle: "a1b2", action: "with", rest: "views, likes" },
      "#h"                      => { handle: "h",    action: nil,    rest: "" },
      "  #h visit studio"       => { handle: "h",    action: "visit", rest: "studio" }
    }.each do |input, expected|
      it "#{input.inspect} → #{expected}" do
        expect(parsed_intent(input)).to include(stack: :hashtag, **expected)
      end
    end
  end

  describe "per-target action gating (the reply matrix)" do
    # Each follow-up target accepts a declared set of action verbs. Assert the
    # registry exposes them (this is what gates ToolDelegator + drives suggestions).
    {
      "video_detail"     => %w[rm delete reindex link unlink shinies sync],
      "game_detail"      => %w[rm delete reindex link unlink shinies sync],
      "channel_detail"   => %w[visit sync],
      "video_list"       => %w[show delete rm with without sort order],
      "game_list"        => %w[with without sort order],
      "channel_list"     => %w[shinies],
      "analytics_glance" => %w[with without analyze],
      "analyze_message"  => %w[with without],
      "channel_visit"    => %w[]
    }.each do |target, expected_actions|
      it "#{target} accepts #{expected_actions.inspect}" do
        actual = Pito::FollowUp::Registry.actions_for(target).map(&:to_s)
        expected_actions.each { |a| expect(actual).to include(a), "#{target} should accept #{a}" }
      end
    end

    it "the new sync/analyze reply actions are gated in" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("sync")
      expect(Pito::FollowUp::Registry.actions_for("game_detail")).to include("sync")
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("sync")
      expect(Pito::FollowUp::Registry.actions_for("analytics_glance")).to include("analyze")
    end
  end

  describe "unknown targets / actions" do
    it "an unknown target resolves to no handler and no actions" do
      expect(Pito::FollowUp::Registry.for("bogus_target")).to be_nil
      expect(Pito::FollowUp::Registry.actions_for("bogus_target")).to eq([])
    end

    it "an action not in a target's matrix is not gated in" do
      expect(Pito::FollowUp::Registry.actions_for("channel_list")).not_to include("sync")
      expect(Pito::FollowUp::Registry.actions_for("analyze_message")).not_to include("analyze")
    end

    it "price/platform are gated OUT of game_detail/game_list (retired standalone tools, Q16/Q16b)" do
      expect(Pito::FollowUp::Registry.actions_for("game_detail")).not_to include("price", "platform")
      expect(Pito::FollowUp::Registry.actions_for("game_list")).not_to include("price", "platform")
    end
  end
end
