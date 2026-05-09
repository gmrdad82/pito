require "rails_helper"

# Phase 7.5 — Step 04. Help modal that mirrors the `pito` CLI's help
# overlay (`extras/cli/src/ui/help.rs`). Locked decision Q6: the CLI
# is the source of truth — every binding the CLI advertises has a row
# here, every CLI section heading has a section here, and we do NOT
# advertise web-only additions.
RSpec.describe KeyboardShortcutsModalComponent, type: :component do
  it "renders a <dialog> element wired to the keyboard controller" do
    render_inline(described_class.new)
    expect(page).to have_css("dialog[data-keyboard-target='dialog'].pane-dialog")
    expect(page).to have_css("dialog[data-action*='click->keyboard#clickOutside']")
  end

  it "renders a [ close ] bracketed link wired to keyboard#close" do
    render_inline(described_class.new)
    expect(page).to have_css('a.bracketed[data-action="click->keyboard#close"]', text: "close")
  end

  describe "section coverage (mirrors CLI help.rs)" do
    before { render_inline(described_class.new) }

    it "renders the general section with `?`, `q`, `n`, and `Esc`" do
      section = page.find(".keyboard-shortcuts-section", text: /general/i)
      expect(section).to have_css("span.keycap", text: "?")
      expect(section).to have_css("span.keycap", text: "q")
      expect(section).to have_css("span.keycap", text: "n")
      expect(section).to have_css("span.keycap", text: "Esc")
      expect(section).to have_text("toggle this help")
      expect(section).to have_text("toggle dark/light theme")
    end

    it "renders the navigation section with every g-prefix binding" do
      section = page.find(".keyboard-shortcuts-section", text: /navigation/i)
      [ "g d", "g c", "g v", "g s", "g e" ].each do |combo|
        keys = combo.split(" ")
        keys.each { |k| expect(section).to have_css("span.keycap", text: k) }
      end
      expect(section).to have_text("dashboard")
      expect(section).to have_text("channels")
      expect(section).to have_text("videos")
      expect(section).to have_text("saved views")
      expect(section).to have_text("settings")
    end

    it "renders the list-pages section with j/k/space/b/s/D/Y and f-prefix" do
      section = page.find(".keyboard-shortcuts-section", text: /list pages/i)
      %w[j k space b s D Y / f].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text(/bulk/i)
      expect(section).to have_text(/starred/i)
      expect(section).to have_text(/connected/i)
    end

    it "renders the detail-pages section with v / s / Y / D" do
      section = page.find(".keyboard-shortcuts-section", text: /detail pages/i)
      %w[v s Y D].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text("view URL in browser")
    end

    it "renders the confirmation-prompts section with `y` and Esc" do
      section = page.find(".keyboard-shortcuts-section", text: /confirmation/i)
      expect(section).to have_css("span.keycap", text: "y")
      expect(section).to have_css("span.keycap", text: "Esc")
      expect(section).to have_text("confirm")
      expect(section).to have_text("cancel")
    end
  end

  it "does NOT advertise the retired `f y` filter (mirrors CLI parity sweep)" do
    render_inline(described_class.new)
    # `f y` (filter: syncing) was dropped after Path A2; the CLI's help
    # overlay was scrubbed of it in the same pass and Rails follows.
    expect(page).to have_no_text(/filter:\s*syncing/i)
    expect(page).to have_no_text("f y")
  end

  it "does not introduce a JS confirm / alert / prompt anywhere" do
    render_inline(described_class.new)
    rendered = page.native.to_html
    expect(rendered).not_to include("data-turbo-confirm")
    expect(rendered).not_to include("window.confirm")
    expect(rendered).not_to include("alert(")
    expect(rendered).not_to include("prompt(")
  end
end
