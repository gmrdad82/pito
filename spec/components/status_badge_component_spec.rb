require "rails_helper"

# Shared bordered status badge. The canonical class is `.status-badge`;
# each kind paints border + text color via a `--<kind>` modifier. The
# label renders as plain text — the border IS the visual delimiter.
RSpec.describe StatusBadgeComponent, type: :component do
  describe "rendering" do
    it "renders a bordered span with the label as plain text" do
      render_inline(described_class.new(label: "info", kind: :info))
      expect(page).to have_css("span.status-badge", text: "info")
    end

    it "renders the label WITHOUT literal `[` `]` characters" do
      render_inline(described_class.new(label: "all day", kind: :all_day))
      badge = page.find("span.status-badge")
      expect(badge.text).not_to include("[")
      expect(badge.text).not_to include("]")
    end

    it "applies the per-kind modifier class for :info" do
      render_inline(described_class.new(label: "info", kind: :info))
      expect(page).to have_css("span.status-badge.status-badge--info")
    end

    it "applies the per-kind modifier class for :success" do
      render_inline(described_class.new(label: "success", kind: :success))
      expect(page).to have_css("span.status-badge.status-badge--success")
    end

    it "applies the per-kind modifier class for :warn" do
      render_inline(described_class.new(label: "warn", kind: :warn))
      expect(page).to have_css("span.status-badge.status-badge--warn")
    end

    it "applies the per-kind modifier class for :urgent" do
      render_inline(described_class.new(label: "urgent", kind: :urgent))
      expect(page).to have_css("span.status-badge.status-badge--urgent")
    end

    it "applies the per-kind modifier class for :neutral" do
      render_inline(described_class.new(label: "neutral", kind: :neutral))
      expect(page).to have_css("span.status-badge.status-badge--neutral")
    end

    it "applies the per-kind modifier class for :yes" do
      render_inline(described_class.new(label: "yes", kind: :yes))
      expect(page).to have_css("span.status-badge.status-badge--yes")
    end

    it "applies the per-kind modifier class for :no" do
      render_inline(described_class.new(label: "no", kind: :no))
      expect(page).to have_css("span.status-badge.status-badge--no")
    end

    it "applies the per-kind modifier class for :all_day" do
      render_inline(described_class.new(label: "all day", kind: :all_day))
      expect(page).to have_css("span.status-badge.status-badge--all_day")
    end
  end

  describe "kind coercion" do
    it "accepts string kinds and coerces to symbol" do
      render_inline(described_class.new(label: "info", kind: "info"))
      expect(page).to have_css("span.status-badge.status-badge--info")
    end

    it "falls back to :neutral for an unknown kind (rather than raising)" do
      render_inline(described_class.new(label: "anything", kind: :something_weird))
      expect(page).to have_css("span.status-badge.status-badge--neutral")
    end

    it "falls back to :neutral when kind is nil" do
      render_inline(described_class.new(label: "x", kind: nil))
      expect(page).to have_css("span.status-badge.status-badge--neutral")
    end

    it "defaults to :neutral when kind is omitted" do
      render_inline(described_class.new(label: "x"))
      expect(page).to have_css("span.status-badge.status-badge--neutral")
    end
  end

  describe "API contract" do
    it "exposes the supported kinds via the KINDS constant" do
      expect(described_class::KINDS).to include(
        :info, :success, :warn, :urgent, :neutral, :yes, :no, :all_day
      )
    end
  end
end
