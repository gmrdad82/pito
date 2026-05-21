require "rails_helper"

# FB-170 (2026-05-21) — V6 `:command` palette ViewComponent spec.
#
# Locks the rendered DOM contract:
#   * hidden by default (no surface until `:` opens it)
#   * `data-controller="tui-command-palette"` wired on the root
#   * input element + suggestion list container present
#   * commands serialized into the
#     `data-tui-command-palette-commands-value` attribute as JSON
#   * footer hint copy locked
#
# Note on Capybara visibility: the root carries `hidden` so the entire
# palette tree is visually hidden. Capybara's default `find` ignores
# hidden elements, so every assertion below opts in via
# `visible: :all`.
RSpec.describe Tui::CommandPaletteComponent, type: :component do
  let(:sample_commands) do
    [
      { name: "home", hint: "go to home", path: -> { "/" } },
      { name: "settings", hint: "go to settings", path: -> { "/settings" } },
      { name: "help", hint: "open help dialog", action: :open_help }
    ]
  end

  describe "root element" do
    it "renders the palette hidden by default" do
      render_inline(described_class.new(commands: sample_commands))

      expect(page).to have_css(".tui-command-palette[hidden]", visible: :all)
    end

    it "wires the Stimulus controller via data-controller=tui-command-palette" do
      render_inline(described_class.new(commands: sample_commands))

      expect(page).to have_css(
        '.tui-command-palette[data-controller="tui-command-palette"]',
        visible: :all
      )
    end
  end

  describe "input + list + footer" do
    before { render_inline(described_class.new(commands: sample_commands)) }

    it "renders the vim-line `:` prompt" do
      expect(page).to have_css(".tui-command-palette__prompt", text: ":", visible: :all)
    end

    it "renders the input element" do
      expect(page).to have_css("input.tui-command-palette__input", visible: :all)
    end

    it "renders the suggestion list container with the Stimulus target" do
      expect(page).to have_css(
        '.tui-command-palette__list[data-tui-command-palette-target="list"]',
        visible: :all
      )
    end

    it "renders the footer hint copy" do
      expect(page).to have_css(".tui-command-palette__foot", text: /Tab cycle/, visible: :all)
      expect(page).to have_css(".tui-command-palette__foot", text: /Enter run/, visible: :all)
      expect(page).to have_css(".tui-command-palette__foot", text: /Esc close/, visible: :all)
    end
  end

  describe "commands serialization" do
    it "exposes the commands list as a JSON data attribute" do
      render_inline(described_class.new(commands: sample_commands))

      attr = page.find(".tui-command-palette", visible: :all)["data-tui-command-palette-commands-value"]
      json = JSON.parse(attr)

      expect(json).to be_an(Array)
      expect(json.length).to eq(3)
      expect(json.map { |c| c["name"] }).to eq(%w[home settings help])
    end

    it "resolves path Procs to strings in the wire format" do
      render_inline(described_class.new(commands: sample_commands))

      attr = page.find(".tui-command-palette", visible: :all)["data-tui-command-palette-commands-value"]
      json = JSON.parse(attr)

      home = json.find { |c| c["name"] == "home" }
      expect(home["path"]).to eq("/")
    end

    it "carries action commands without a path" do
      render_inline(described_class.new(commands: sample_commands))

      attr = page.find(".tui-command-palette", visible: :all)["data-tui-command-palette-commands-value"]
      json = JSON.parse(attr)

      help = json.find { |c| c["name"] == "help" }
      expect(help["action"]).to eq("open_help")
      expect(help["path"]).to be_nil
    end

    it "includes the method when set on a command" do
      commands = [
        { name: "logout", hint: "logout", method: :delete, path: -> { "/session" } }
      ]
      render_inline(described_class.new(commands: commands))

      attr = page.find(".tui-command-palette", visible: :all)["data-tui-command-palette-commands-value"]
      json = JSON.parse(attr)

      logout = json.find { |c| c["name"] == "logout" }
      expect(logout["method"]).to eq("delete")
      expect(logout["path"]).to eq("/session")
    end

    it "renders gracefully with an empty commands list" do
      render_inline(described_class.new(commands: []))

      attr = page.find(".tui-command-palette", visible: :all)["data-tui-command-palette-commands-value"]
      expect(JSON.parse(attr)).to eq([])
    end
  end
end
