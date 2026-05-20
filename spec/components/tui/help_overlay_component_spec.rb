require "rails_helper"

# Beta 4 — Phase F1. Locks the rendered DOM contract for the
# `Tui::HelpOverlayComponent`. The overlay is a `<dialog>`-backed
# which-key-style reference surface listing every top-level
# keybinding pito supports, grouped by category. It is mounted in
# `app/views/layouts/application.html.erb` and toggled by the
# `tui-help-overlay` Stimulus controller.
#
# What this spec locks (drift in any of these silently changes the
# user-facing help surface):
#
#   * the four canonical groups (global / section nav / panel nav /
#     session)
#   * the bracketed key format ([?], [SPACE], [g h], [TAB], [q Q],
#     [ESC])
#   * the `<dialog>` root with the `tui-help-overlay` Stimulus
#     controller wired on it
#   * the `tui-help-overlay__group-title` class hook on group titles
#     (the section accent cascade attaches via this hook)
RSpec.describe Tui::HelpOverlayComponent, type: :component do
  describe "root element" do
    it "renders inside a <dialog> element" do
      render_inline(described_class.new)
      expect(page).to have_css("dialog#tui-help-overlay.tui-help-overlay")
    end

    it "wires the Stimulus controller via data-controller=tui-help-overlay" do
      render_inline(described_class.new)
      expect(page).to have_css('dialog[data-controller="tui-help-overlay"]')
    end

    it "renders an inner panel for the overlay body" do
      render_inline(described_class.new)
      expect(page).to have_css("dialog .tui-help-overlay__panel")
    end

    it "renders an `[Esc] to close` hint in the header" do
      render_inline(described_class.new)
      expect(page).to have_css(".tui-help-overlay__close", text: /esc.*close/i)
    end

    it "renders a lowercase `help` title in the header" do
      render_inline(described_class.new)
      expect(page).to have_css(".tui-help-overlay__title", text: "help")
    end
  end

  describe "groups" do
    before { render_inline(described_class.new) }

    it "renders exactly 4 groups" do
      expect(page).to have_css(".tui-help-overlay__group", count: 4)
    end

    %w[global].each do |title|
      it "renders the `#{title}` group" do
        expect(page).to have_css(".tui-help-overlay__group-title", text: title)
      end
    end

    it "renders the `section nav` group" do
      expect(page).to have_css(".tui-help-overlay__group-title", text: "section nav")
    end

    it "renders the `panel nav` group" do
      expect(page).to have_css(".tui-help-overlay__group-title", text: "panel nav")
    end

    it "renders the `session` group" do
      expect(page).to have_css(".tui-help-overlay__group-title", text: "session")
    end

    it "uses `.tui-help-overlay__group-title` as the hook for the section accent cascade" do
      # The section accent (set by `body[data-section]` in
      # application.html.erb) cascades down into every overlay group
      # title via `.tui-help-overlay__group-title`. Renaming this hook
      # silently kills the accent coloring.
      expect(page).to have_css(".tui-help-overlay__group-title", count: 4)
    end
  end

  describe "global group keys" do
    before { render_inline(described_class.new) }

    it "renders the `?` open-help key bracketed" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[?]")
    end

    it "renders the `:` command-palette key bracketed" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[:]")
    end

    it "renders the `/` search key bracketed" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[/]")
    end

    it "renders the `Space` leader-menu key bracketed" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[Space]")
    end
  end

  describe "section nav group keys" do
    before { render_inline(described_class.new) }

    %w[g\ h g\ C g\ c g\ v g\ p g\ g g\ n g\ s].each do |key|
      it "renders the `[#{key}]` chord" do
        expect(page).to have_css(".tui-help-overlay__key", text: "[#{key}]")
      end
    end
  end

  describe "panel nav group keys" do
    before { render_inline(described_class.new) }

    it "renders the `TAB` cycle-forward key" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[TAB]")
    end

    it "renders the `Shift-TAB` cycle-backward chord" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[Shift-TAB]")
    end

    %w[h l k j].each do |letter|
      it "renders the `Ctrl-#{letter}` panel-direction chord" do
        expect(page).to have_css(".tui-help-overlay__key", text: "[Ctrl-#{letter}]")
      end
    end
  end

  describe "session group keys" do
    before { render_inline(described_class.new) }

    it "renders the `q Q` logout chord" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[q Q]")
    end

    it "renders the `Esc` close-modal key" do
      expect(page).to have_css(".tui-help-overlay__key", text: "[Esc]")
    end
  end

  describe "key / label pairing" do
    before { render_inline(described_class.new) }

    it "renders each key inside a `<dt>` and each label inside a `<dd>`" do
      expect(page).to have_css("dl.tui-help-overlay__keys dt.tui-help-overlay__key")
      expect(page).to have_css("dl.tui-help-overlay__keys dd.tui-help-overlay__label")
    end

    it "renders each label in lowercase" do
      # Spot-check a handful — every <dd> rendered should be the bare
      # lowercase phrase from GROUPS without any uppercase mutation.
      expect(page).to have_css(".tui-help-overlay__label", text: "open this help")
      expect(page).to have_css(".tui-help-overlay__label", text: "command palette")
      expect(page).to have_css(".tui-help-overlay__label", text: "leader menu")
      expect(page).to have_css(".tui-help-overlay__label", text: "cycle panel forward")
      expect(page).to have_css(".tui-help-overlay__label", text: "logout")
    end

    it "pairs every <dt> with a matching <dd> in the same group" do
      total_keys   = page.all(".tui-help-overlay__key").length
      total_labels = page.all(".tui-help-overlay__label").length
      expect(total_keys).to eq(total_labels)
      expect(total_keys).to be > 0
    end
  end

  describe "GROUPS constant" do
    it "is frozen" do
      expect(described_class::GROUPS).to be_frozen
    end

    it "contains exactly four groups" do
      expect(described_class::GROUPS.length).to eq(4)
    end

    it "names the groups in the canonical render order" do
      titles = described_class::GROUPS.map { |g| g[:title] }
      expect(titles).to eq([ "global", "section nav", "panel nav", "session" ])
    end

    it "describes the logout chord as `q Q` in the session group" do
      session = described_class::GROUPS.find { |g| g[:title] == "session" }
      logout = session[:items].find { |i| i[:label] == "logout" }
      expect(logout[:key]).to eq("q Q")
    end
  end
end
