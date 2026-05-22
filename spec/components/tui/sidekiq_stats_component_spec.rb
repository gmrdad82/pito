# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::SidekiqStatsComponent, type: :component do
  let(:busy_prefix)     { I18n.t("tui.tst.sidekiq.busy_prefix") }
  let(:enqueued_prefix) { I18n.t("tui.tst.sidekiq.enqueued_prefix") }
  let(:retry_prefix)    { I18n.t("tui.tst.sidekiq.retry_prefix") }

  describe "all zeroes" do
    subject(:component) { described_class.new(busy: 0, enqueued: 0, retry: 0) }

    it "renders without raising" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "gives all cells the sk-zero muted class" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-zero", count: 3)
    end

    it "uses i18n prefixes (not hardcoded letters)" do
      render_inline(component)
      expect(page).to have_text("#{busy_prefix}0")
      expect(page).to have_text("#{enqueued_prefix}0")
      expect(page).to have_text("#{retry_prefix}0")
    end
  end

  describe "busy non-zero" do
    subject(:component) { described_class.new(busy: 3, enqueued: 0, retry: 0) }

    it "gives the busy cell the sk-b class" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-b", text: "#{busy_prefix}3")
    end

    it "keeps enqueued and retry cells as sk-zero" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-zero", count: 2)
    end
  end

  describe "enqueued non-zero" do
    subject(:component) { described_class.new(busy: 0, enqueued: 5, retry: 0) }

    it "gives the enqueued cell the sk-e class" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-e", text: "#{enqueued_prefix}5")
    end

    it "keeps busy and retry cells as sk-zero" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-zero", count: 2)
    end
  end

  describe "retry non-zero" do
    subject(:component) { described_class.new(busy: 0, enqueued: 0, retry: 2) }

    it "gives the retry cell the sk-r danger class" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-r", text: "#{retry_prefix}2")
    end

    it "keeps busy and enqueued cells as sk-zero" do
      render_inline(component)
      expect(page).to have_css(".sb-sk-cell.sk-zero", count: 2)
    end
  end

  describe "Stimulus data-* target attrs" do
    subject(:component) { described_class.new(busy: 1, enqueued: 2, retry: 3) }

    it "marks the busy cell with the correct Stimulus target" do
      render_inline(component)
      expect(page).to have_css("[data-tui-sidekiq-stats-target='busy']")
    end

    it "marks the enqueued cell with the correct Stimulus target" do
      render_inline(component)
      expect(page).to have_css("[data-tui-sidekiq-stats-target='enqueued']")
    end

    it "marks the retry cell with the correct Stimulus target" do
      render_inline(component)
      expect(page).to have_css("[data-tui-sidekiq-stats-target='retry']")
    end

    # FB-test-infra (2026-05-22) — Regression: the three i18n prefix
    # data-* values the child `tui-sidekiq-stats` controller reads on
    # connect MUST be present on the root span. Without them the JS
    # rebuilds cells as `<undefined>3` instead of `b3`. The payload key
    # contract (`busy` / `enqueued` / `retry`) is the same the test
    # rake (`pito:test:broadcast_sidekiq`) ships via the canonical
    # `kind: "sidekiq"` envelope.
    it "seeds the three prefix values on the root span" do
      render_inline(component)
      expect(page).to have_css("[data-tui-sidekiq-stats-busy-prefix-value]")
      expect(page).to have_css("[data-tui-sidekiq-stats-enqueued-prefix-value]")
      expect(page).to have_css("[data-tui-sidekiq-stats-retry-prefix-value]")
    end
  end
end
