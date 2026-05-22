require "rails_helper"

RSpec.describe Tui::CommandPaletteComponent, type: :component do
  let(:commands) { Tui::CommandRegistry.commands_for(:home) }

  subject(:component) { described_class.new(commands: commands) }

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  describe "root container" do
    before { render_inline(component) }

    it "renders a <div> (not <dialog>)" do
      expect(page).to have_css("div.tui-command-palette", visible: :all)
      expect(page).not_to have_css("dialog", visible: :all)
    end

    it "has the hidden attribute by default" do
      expect(page).to have_css("div.tui-command-palette[hidden]", visible: :all)
    end

    it "carries data-controller for Stimulus" do
      expect(page).to have_css("[data-controller='tui-command-palette']", visible: :all)
    end

    it "carries data-tui-command-palette-commands-value attribute" do
      expect(page).to have_css("[data-tui-command-palette-commands-value]", visible: :all)
    end

    it "carries data-tui-command-palette-empty-value with i18n empty string" do
      empty_text = I18n.t("tui.command_palette.empty")
      expect(page).to have_css("[data-tui-command-palette-empty-value='#{empty_text}']", visible: :all)
    end
  end

  describe "commands serialization" do
    it "encodes all 6 global commands into commands_value JSON" do
      render_inline(component)
      raw = page.find("[data-tui-command-palette-commands-value]", visible: :all)
                .native["data-tui-command-palette-commands-value"]
      parsed = JSON.parse(raw)
      expect(parsed.length).to eq(6)
    end

    it "includes home command with resolved path" do
      render_inline(component)
      raw = page.find("[data-tui-command-palette-commands-value]", visible: :all)
                .native["data-tui-command-palette-commands-value"]
      parsed = JSON.parse(raw)
      home = parsed.find { |c| c["name"] == I18n.t("tui.commands.home.name") }
      expect(home).to be_present
      expect(home["path"]).to eq("/")
    end

    it "includes logout command with delete method" do
      render_inline(component)
      raw = page.find("[data-tui-command-palette-commands-value]", visible: :all)
                .native["data-tui-command-palette-commands-value"]
      parsed = JSON.parse(raw)
      logout = parsed.find { |c| c["name"] == I18n.t("tui.commands.logout.name") }
      expect(logout).to be_present
      expect(logout["method"]).to eq("delete")
    end
  end

  describe "footer hints" do
    before { render_inline(component) }

    it "renders the 'next' footer hint from i18n" do
      expect(page).to have_css("span", text: I18n.t("tui.command_palette.footer.next"), visible: :all)
    end

    it "renders the 'cycle' footer hint from i18n" do
      expect(page).to have_css("span", text: I18n.t("tui.command_palette.footer.cycle"), visible: :all)
    end

    it "renders the 'run' footer hint from i18n" do
      expect(page).to have_css("span", text: I18n.t("tui.command_palette.footer.run"), visible: :all)
    end

    it "renders the 'close' footer hint from i18n" do
      expect(page).to have_css("span", text: I18n.t("tui.command_palette.footer.close"), visible: :all)
    end

    it "renders separator glyphs from i18n between hints" do
      sep = I18n.t("tui.command_palette.separator")
      expect(page).to have_css("span.tui-command-palette__sep", text: sep, minimum: 3, visible: :all)
    end
  end

  describe "input line" do
    before { render_inline(component) }

    it "renders the prompt glyph" do
      expect(page).to have_css("span.tui-command-palette__prompt", text: ":", visible: :all)
    end

    it "renders the text input" do
      expect(page).to have_css("input.tui-command-palette__input[type='text']", visible: :all)
    end

    it "renders the input with prompt_placeholder from i18n" do
      placeholder = I18n.t("tui.command_palette.prompt_placeholder")
      expect(page).to have_css("input[placeholder='#{placeholder}']", visible: :all)
    end

    it "wires the Stimulus filter and keydown actions on the input" do
      expect(page).to have_css(
        "input[data-action='input->tui-command-palette#filter keydown->tui-command-palette#keydown']",
        visible: :all
      )
    end
  end

  describe "suggestion list target" do
    it "renders the list container for Stimulus to populate" do
      render_inline(component)
      expect(page).to have_css("[data-tui-command-palette-target='list']", visible: :all)
    end
  end

  describe "empty commands list" do
    subject(:component) { described_class.new(commands: []) }

    it "renders without raising when commands is empty" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "encodes an empty JSON array into commands-value" do
      render_inline(component)
      raw = page.find("[data-tui-command-palette-commands-value]", visible: :all)
                .native["data-tui-command-palette-commands-value"]
      expect(JSON.parse(raw)).to eq([])
    end
  end
end
