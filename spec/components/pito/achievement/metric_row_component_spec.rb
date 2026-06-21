# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::MetricRowComponent, type: :component do
  let!(:game) { create(:game, title: "Lies of P") }
  let(:metric) { "views" }

  subject(:component) { described_class.new(entity: game, metric: metric) }

  # ── label ──────────────────────────────────────────────────────────────────────

  describe "#label" do
    it "returns the full word metric label" do
      expect(component.label).to eq(Pito::Achievements::Label.for("views"))
    end
  end

  # ── current_value ──────────────────────────────────────────────────────────────

  describe "#current_value" do
    context "when no AchievementMetric exists" do
      it "returns 0" do
        expect(component.current_value).to eq(0)
      end
    end

    context "when an AchievementMetric exists" do
      before { create(:achievement_metric, achievable: game, metric: "views", value: 1500) }

      it "returns the metric value" do
        expect(component.current_value).to eq(1500)
      end
    end
  end

  # ── obtained_achievements ──────────────────────────────────────────────────────

  describe "#obtained_achievements" do
    context "when no achievements exist" do
      it "returns an empty relation" do
        expect(component.obtained_achievements).to be_empty
      end
    end

    context "when achievements exist for this metric" do
      before do
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 100)
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 1000)
      end

      it "returns achievements ordered by unlocked_at" do
        results = component.obtained_achievements
        expect(results.size).to be >= 2
        expect(results.map(&:unlocked_at)).to eq(results.map(&:unlocked_at).sort)
      end

      it "returns only achievements for the given metric" do
        expect(component.obtained_achievements.map(&:metric).uniq).to eq([ "views" ])
      end
    end

    context "when achievements exist for a different metric" do
      before do
        Pito::Achievements::Evaluate.call(achievable: game, metric: "likes", value: 10)
      end

      it "returns no achievements for the views metric" do
        expect(component.obtained_achievements).to be_empty
      end
    end
  end

  # ── rendered HTML ──────────────────────────────────────────────────────────────

  describe "rendered output" do
    context "with no obtained shinies" do
      it "render? is false" do
        expect(component.render?).to be(false)
      end

      it "renders nothing — no track, no label" do
        html = render_inline(component).to_html
        expect(html).not_to include("pito-achievement-metric-row")
        expect(html).not_to include("pito-achievement-track")
      end
    end

    context "with obtained achievements" do
      before do
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 10)
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 100)
      end

      subject(:html) { render_inline(described_class.new(entity: game, metric: "views")).to_html }

      it "includes the metric row wrapper" do
        expect(html).to include("pito-achievement-metric-row")
      end

      it "includes a TrackComponent" do
        expect(html).to include("pito-achievement-track")
      end

      it "includes a badges container" do
        expect(html).to include("pito-achievement-metric-row__badges")
      end

      it "renders BadgeComponents for each obtained threshold" do
        # Thresholds 1, 2, 5, 10 are below 100; expect at least 2 badges (10 + ≤ earlier ones).
        expect(html.scan("pito-achievement-badge").size).to be >= 2
      end

      it "renders upcoming dots for thresholds not yet reached" do
        expect(html).to include("pito-achievement-track__dot--upcoming")
      end
    end
  end
end
