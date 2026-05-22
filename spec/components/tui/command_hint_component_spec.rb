require "rails_helper"

RSpec.describe Tui::CommandHintComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the command key glyph" do
    expect(page).to have_css("span.bsb-hint-key", text: I18n.t("tui.bst.command_key"))
  end

  it "renders the command label" do
    expect(page).to have_css("span.bsb-hint-label")
    expect(page).to have_text(I18n.t("tui.bst.command_label"))
  end

  it "renders the : glyph specifically" do
    expect(page).to have_css("span.bsb-hint-key", text: ":")
  end

  it "accepts no kwargs" do
    expect { described_class.new }.not_to raise_error
  end

  it "does not produce translation missing strings" do
    expect(page.text).not_to include("translation missing")
  end
end
