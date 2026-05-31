# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::Slash::Component do
  # Commands use description_key which maps to i18n translations.
  # Keys from config/locales/pito/palette/en.yml (pito.palette.slash.descriptions.*)
  let(:cmd_authenticate) do
    { verb: "authenticate", description_key: "pito.palette.slash.descriptions.authenticate" }
  end
  let(:cmd_channels) do
    { verb: "channels", description_key: "pito.palette.slash.descriptions.channels" }
  end
  let(:cmd_videos) do
    { verb: "videos", description_key: "pito.palette.slash.descriptions.videos" }
  end
  let(:cmd_help) do
    { verb: "help", description_key: "pito.palette.slash.descriptions.help" }
  end

  # ──────────────────────────────────────────
  # Initializer defaults
  # ──────────────────────────────────────────
  describe "#initialize" do
    it "accepts commands with default selected_index and typed" do
      comp = described_class.new(commands: [ cmd_authenticate ])
      expect(comp).to be_a(described_class)
    end

    it "accepts explicit selected_index" do
      comp = described_class.new(commands: [ cmd_authenticate, cmd_channels ], selected_index: 1)
      expect(comp).to be_a(described_class)
    end

    it "accepts an explicit typed string" do
      comp = described_class.new(commands: [ cmd_authenticate ], typed: "/aut")
      expect(comp).to be_a(described_class)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: structural chrome
  # ──────────────────────────────────────────
  describe "rendered structure" do
    let(:node) { render_inline(described_class.new(commands: [ cmd_authenticate ])) }

    it "renders the outer flex container" do
      expect(node.css("div.flex").first).not_to be_nil
    end

    it "renders the purple accent bar" do
      accent = node.css("div[style*='background: var(--accent-purple)']")
      expect(accent.first).not_to be_nil
    end

    it "renders the horizontal divider" do
      divider = node.css("div[style*='height: 1px']")
      expect(divider.first).not_to be_nil
    end

    it "renders the cursor component inside the input echo line" do
      # Cursor renders a / character in a small glyph element
      expect(node.text).to include("/")
    end
  end

  # ──────────────────────────────────────────
  # Rendering: empty commands list
  # ──────────────────────────────────────────
  describe "with no commands" do
    it "renders without crashing" do
      node = render_inline(described_class.new(commands: []))
      expect(node.to_html).not_to be_empty
    end

    it "renders the chrome (accent bar, divider) even with no commands" do
      node = render_inline(described_class.new(commands: []))
      expect(node.css("div[style*='background: var(--accent-purple)']").first).not_to be_nil
    end
  end

  # ──────────────────────────────────────────
  # Rendering: single command
  # ──────────────────────────────────────────
  describe "with a single command" do
    let(:node) { render_inline(described_class.new(commands: [ cmd_authenticate ])) }

    it "renders the verb prefixed with /" do
      expect(node.css("span.text-fg").map(&:text)).to include(include("/authenticate"))
    end

    it "renders the translated description" do
      expect(node.text).to include("Authenticate to access pito")
    end

    it "renders the description in a text-fg-dim span" do
      descriptions = node.css("span.text-fg-dim").map(&:text)
      expect(descriptions).to include("Authenticate to access pito")
    end
  end

  # ──────────────────────────────────────────
  # Rendering: multiple commands
  # ──────────────────────────────────────────
  describe "with multiple commands" do
    let(:commands) { [ cmd_authenticate, cmd_channels, cmd_videos ] }
    let(:node) { render_inline(described_class.new(commands: commands, selected_index: 0)) }

    it "renders all command verbs" do
      verbs = node.css("span.text-fg").map(&:text)
      expect(verbs).to include(include("/authenticate"))
      expect(verbs).to include(include("/channels"))
      expect(verbs).to include(include("/videos"))
    end

    it "renders all descriptions" do
      expect(node.text).to include("Authenticate to access pito")
      expect(node.text).to include("List your YouTube channels")
      expect(node.text).to include("List videos for a channel")
    end
  end

  # ──────────────────────────────────────────
  # Selection highlight
  # ──────────────────────────────────────────
  describe "selection highlight" do
    let(:commands) { [ cmd_authenticate, cmd_channels, cmd_help ] }

    # Command rows have `padding: 2px 10px` in their style; the horizontal divider
    # also uses `background: var(--border-default)` but has `height: 1px` instead.
    # Scoping to rows that include `padding: 2px 10px` isolates command rows only.
    def selected_command_rows(node)
      node.css("div[style*='padding: 2px 10px'][style*='background: var(--border-default)']")
    end

    it "highlights exactly one command row" do
      node = render_inline(described_class.new(commands: commands, selected_index: 0))
      expect(selected_command_rows(node).length).to eq(1)
    end

    it "highlights the first command when selected_index is 0" do
      node = render_inline(described_class.new(commands: commands, selected_index: 0))
      expect(selected_command_rows(node).first.text).to include("/authenticate")
    end

    it "highlights the second command when selected_index is 1" do
      node = render_inline(described_class.new(commands: commands, selected_index: 1))
      expect(selected_command_rows(node).first.text).to include("/channels")
    end

    it "highlights the last command when selected_index points to it" do
      node = render_inline(described_class.new(commands: commands, selected_index: 2))
      expect(selected_command_rows(node).first.text).to include("/help")
    end

    it "does not highlight unselected rows" do
      node = render_inline(described_class.new(commands: commands, selected_index: 0))
      all_rows = node.css("div[style*='padding: 2px 10px']")
      unhighlighted = all_rows.reject { |div| div["style"]&.include?("background") }
      expect(unhighlighted.length).to eq(commands.length - 1)
    end
  end

  # ──────────────────────────────────────────
  # Verb column fixed width
  # ──────────────────────────────────────────
  describe "verb span formatting" do
    it "renders verb spans with fixed width style" do
      node = render_inline(described_class.new(commands: [ cmd_authenticate ]))
      verb_spans = node.css("span.text-fg[style*='width: 16ch']")
      expect(verb_spans.first).not_to be_nil
    end
  end

  # ──────────────────────────────────────────
  # Various typed values (stored but not rendered directly)
  # ──────────────────────────────────────────
  describe "typed parameter" do
    it "renders without error when typed is a partial verb" do
      node = render_inline(
        described_class.new(commands: [ cmd_authenticate ], typed: "/aut")
      )
      expect(node.to_html).not_to be_empty
    end

    it "renders without error when typed is just /" do
      node = render_inline(
        described_class.new(commands: [ cmd_channels ], typed: "/")
      )
      expect(node.to_html).not_to be_empty
    end
  end
end
