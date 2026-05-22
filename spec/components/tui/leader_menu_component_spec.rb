require "rails_helper"

RSpec.describe Tui::LeaderMenuComponent, type: :component do
  subject(:component) { described_class.new }

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  describe "dialog chrome" do
    before { render_inline(component) }

    it "renders via Tui::DialogComponent (dialog root present)" do
      expect(page).to have_css("[id='tui-leader-menu']")
    end

    it "renders the i18n title in the dialog border" do
      title = I18n.t("tui.leader.title")
      expect(page).to have_text(title)
    end

    it "carries the tui-leader-menu extra controller" do
      expect(page).to have_css("[data-controller~='tui-leader-menu']")
    end
  end

  describe "default entries" do
    before { render_inline(component) }

    it "renders 7 entry rows (h v g ? : q a)" do
      expect(page).to have_css("li.tui-leader-menu__entry", count: 7)
    end

    it "renders an entry with data-leader-key for each key" do
      %w[h v g ? : q a].each do |key|
        expect(page).to have_css("[data-leader-key='#{key}']")
      end
    end

    it "renders h entry with i18n label 'home'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.h.label"))
    end

    it "renders v entry with i18n label 'videos'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.v.label"))
    end

    it "renders g entry with i18n label 'games'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.g.label"))
    end

    it "renders ? entry with i18n label 'help'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.help.label"))
    end

    it "renders : entry with i18n label 'command'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.command.label"))
    end

    it "renders q entry with i18n label 'logout'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.q.label"))
    end

    it "renders a entry with i18n label 'about'" do
      expect(page).to have_text(I18n.t("tui.leader.entries.a.label"))
    end
  end

  describe "screen_accent kwarg" do
    it "defaults to :home without raising" do
      expect { render_inline(described_class.new(screen_accent: :home)) }.not_to raise_error
    end

    it "accepts :videos accent without raising" do
      expect { render_inline(described_class.new(screen_accent: :videos)) }.not_to raise_error
    end

    it "accepts :games accent without raising" do
      expect { render_inline(described_class.new(screen_accent: :games)) }.not_to raise_error
    end

    it "accepts :settings accent without raising" do
      expect { render_inline(described_class.new(screen_accent: :settings)) }.not_to raise_error
    end
  end

  describe "custom entries override" do
    let(:custom_entries) do
      [
        { key: "x", label_key: "tui.leader.entries.h.label", path: "/custom" }
      ]
    end

    it "renders only the custom entries when provided" do
      render_inline(described_class.new(entries: custom_entries))
      expect(page).to have_css("li.tui-leader-menu__entry", count: 1)
      expect(page).to have_css("[data-leader-key='x']")
    end
  end

  describe "title helper" do
    it "returns the i18n leader title" do
      expect(component.title).to eq(I18n.t("tui.leader.title"))
    end
  end
end
