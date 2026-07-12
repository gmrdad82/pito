# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::Slash::Component do
  # Commands use description_key which maps to i18n translations.
  # Keys from config/locales/pito/palette/en.yml (pito.palette.slash.descriptions.*)
  let(:cmd_login) do
    { tool: "login", description_key: "pito.palette.slash.descriptions.login" }
  end
  let(:cmd_channels) do
    { tool: "channels", description_key: "pito.palette.slash.descriptions.channels" }
  end
  let(:cmd_videos) do
    { tool: "videos", description_key: "pito.palette.slash.descriptions.videos" }
  end
  let(:cmd_help) do
    { tool: "help", description_key: "pito.palette.slash.descriptions.help" }
  end

  # ──────────────────────────────────────────
  # Initializer defaults
  # ──────────────────────────────────────────
  describe "#initialize" do
    it "accepts commands with default selected_index and typed" do
      comp = described_class.new(commands: [ cmd_login ])
      expect(comp).to be_a(described_class)
    end

    it "accepts explicit selected_index" do
      comp = described_class.new(commands: [ cmd_login, cmd_channels ], selected_index: 1)
      expect(comp).to be_a(described_class)
    end

    it "accepts an explicit typed string" do
      comp = described_class.new(commands: [ cmd_login ], typed: "/log")
      expect(comp).to be_a(described_class)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: structural chrome
  # ──────────────────────────────────────────
  describe "rendered structure" do
    let(:node) { render_inline(described_class.new(commands: [ cmd_login ])) }

    it "renders the outer flex container" do
      expect(node.css("div.flex").first).not_to be_nil
    end

    it "renders the purple accent bar" do
      accent = node.css(".pito-segment__bar[data-accent='purple']")
      expect(accent.first).not_to be_nil
    end

    it "renders the horizontal divider" do
      divider = node.css("div.h-px")
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
      expect(node.css(".pito-segment__bar[data-accent='purple']").first).not_to be_nil
    end
  end

  # ──────────────────────────────────────────
  # Rendering: single command
  # ──────────────────────────────────────────
  describe "with a single command" do
    let(:node) { render_inline(described_class.new(commands: [ cmd_login ])) }

    it "renders the tool prefixed with /" do
      expect(node.css("span.text-fg").map(&:text)).to include(include("/login"))
    end

    it "renders the translated description" do
      expect(node.text).to include("Log in to access PITO")
    end

    it "renders the description in a text-fg-dim span" do
      descriptions = node.css("span.text-fg-dim").map(&:text)
      expect(descriptions).to include("Log in to access PITO")
    end
  end

  # ──────────────────────────────────────────
  # Rendering: multiple commands
  # ──────────────────────────────────────────
  describe "with multiple commands" do
    let(:commands) { [ cmd_login, cmd_channels, cmd_videos ] }
    let(:node) { render_inline(described_class.new(commands: commands, selected_index: 0)) }

    it "renders all command tools" do
      tools = node.css("span.text-fg").map(&:text)
      expect(tools).to include(include("/login"))
      expect(tools).to include(include("/channels"))
      expect(tools).to include(include("/videos"))
    end

    it "renders all descriptions" do
      expect(node.text).to include("Log in to access PITO")
      expect(node.text).to include("List your YouTube channels")
      expect(node.text).to include("List vids for a channel")
    end
  end

  # ──────────────────────────────────────────
  # Selection highlight
  # ──────────────────────────────────────────
  describe "selection highlight" do
    let(:commands) { [ cmd_login, cmd_channels, cmd_help ] }

    # Command rows have `py-0.5 px-2.5` classes; the horizontal divider
    # also uses `bg-line-default` but has `h-px` class instead.
    # Scoping to rows that include `px-2.5` isolates command rows only.
    def command_rows(node)
      node.css("div").select { |div| div["class"]&.include?("px-2.5") && div["class"]&.include?("py-0.5") }
    end

    def selected_command_rows(node)
      command_rows(node).select { |div| div["style"]&.include?("background") }
    end

    it "highlights exactly one command row" do
      node = render_inline(described_class.new(commands: commands, selected_index: 0))
      expect(selected_command_rows(node).length).to eq(1)
    end

    it "highlights the first command when selected_index is 0" do
      node = render_inline(described_class.new(commands: commands, selected_index: 0))
      expect(selected_command_rows(node).first.text).to include("/login")
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
      unhighlighted = command_rows(node).reject { |div| div["style"]&.include?("background") }
      expect(unhighlighted.length).to eq(commands.length - 1)
    end
  end

  # ──────────────────────────────────────────
  # Tool column fixed width
  # ──────────────────────────────────────────
  describe "tool span formatting" do
    it "renders tool spans with fixed width style" do
      node = render_inline(described_class.new(commands: [ cmd_login ]))
      tool_spans = node.css("span.text-fg[style*='width: 16ch']")
      expect(tool_spans.first).not_to be_nil
    end
  end

  # ──────────────────────────────────────────
  # Various typed values (stored but not rendered directly)
  # ──────────────────────────────────────────
  describe "typed parameter" do
    it "renders without error when typed is a partial tool" do
      node = render_inline(
        described_class.new(commands: [ cmd_login ], typed: "/log")
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
