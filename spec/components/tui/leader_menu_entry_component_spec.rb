require "rails_helper"

RSpec.describe Tui::LeaderMenuEntryComponent, type: :component do
  subject(:component) do
    described_class.new(
      key: "h",
      label: "home",
      data: {
        "leader-key" => "h",
        "leader-path" => "/"
      }
    )
  end

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  describe "row structure" do
    before { render_inline(component) }

    it "renders a <li> with class tui-leader-menu__entry" do
      expect(page).to have_css("li.tui-leader-menu__entry")
    end

    it "renders the key glyph in a span" do
      expect(page).to have_css("span.tui-leader-menu__key", text: "h")
    end

    it "renders the middle-dot separator" do
      expect(page).to have_css("span.tui-leader-menu__sep", text: "·")
    end

    it "renders the label" do
      expect(page).to have_css("span.tui-leader-menu__label", text: "home")
    end
  end

  describe "data-leader-key attribute" do
    it "is forwarded to the <li> root element" do
      render_inline(component)
      expect(page).to have_css("li[data-leader-key='h']")
    end
  end

  describe "path resolution data attr" do
    it "forwards data-leader-path to the <li>" do
      render_inline(component)
      expect(page).to have_css("li[data-leader-path='/']")
    end
  end

  describe "action_name resolution" do
    subject(:component) do
      described_class.new(
        key: "?",
        label: "help",
        data: {
          "leader-key" => "?",
          "leader-action-name" => "open_help"
        }
      )
    end

    it "forwards data-leader-action-name to the <li>" do
      render_inline(component)
      expect(page).to have_css("li[data-leader-action-name='open_help']")
    end

    it "does not render data-leader-path when not provided" do
      render_inline(component)
      expect(page).not_to have_css("li[data-leader-path]")
    end
  end

  describe "dispatch_method resolution" do
    subject(:component) do
      described_class.new(
        key: "a",
        label: "about",
        data: {
          "leader-key" => "a",
          "leader-dispatch-method" => "open_about"
        }
      )
    end

    it "forwards data-leader-dispatch-method to the <li>" do
      render_inline(component)
      expect(page).to have_css("li[data-leader-dispatch-method='open_about']")
    end
  end

  describe "path_method data attr" do
    subject(:component) do
      described_class.new(
        key: "q",
        label: "logout",
        data: {
          "leader-key" => "q",
          "leader-path" => "/session",
          "leader-path-method" => "delete"
        }
      )
    end

    it "forwards data-leader-path-method to the <li>" do
      render_inline(component)
      expect(page).to have_css("li[data-leader-path-method='delete']")
    end
  end

  describe "kwargs" do
    it "exposes key via attr_reader" do
      expect(component.key).to eq("h")
    end

    it "exposes label via attr_reader" do
      expect(component.label).to eq("home")
    end

    it "exposes data via attr_reader" do
      expect(component.data).to include("leader-key" => "h")
    end
  end
end
