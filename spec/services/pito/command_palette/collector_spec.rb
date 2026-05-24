require "rails_helper"

RSpec.describe Pito::CommandPalette::Collector do
  let(:panel_command) do
    { key: "panel_sync", name: "sync toggle", hint: "toggle panel sync", action_name: :sync_toggle }
  end
  let(:sub_panel_command) do
    { key: "sub_panel_reindex", name: "reindex", hint: "rebuild index", action_name: :reindex_meilisearch }
  end
  let(:screen_command) do
    { key: "screen_home", name: "home", hint: "go to home", path: "/" }
  end

  describe ".call" do
    it "returns an empty array when all scopes are empty" do
      expect(described_class.call).to eq([])
    end

    it "concatenates sub_panel → panel → screen in that order" do
      result = described_class.call(
        panel_commands: [ panel_command ],
        sub_panel_commands: [ sub_panel_command ],
        screen_commands: [ screen_command ]
      )
      expect(result.map { |c| c[:key] }).to eq(%w[sub_panel_reindex panel_sync screen_home])
    end

    it "annotates each command with the correct scope" do
      result = described_class.call(
        panel_commands: [ panel_command ],
        sub_panel_commands: [ sub_panel_command ],
        screen_commands: [ screen_command ]
      )
      expect(result.map { |c| c[:scope] }).to eq([ :sub_panel, :panel, :screen ])
    end

    it "preserves an explicit :scope already set on a command" do
      pre_tagged = panel_command.merge(scope: :screen)
      result = described_class.call(panel_commands: [ pre_tagged ])
      expect(result.first[:scope]).to eq(:screen)
    end

    it "does not mutate the input arrays" do
      input = [ panel_command ]
      described_class.call(panel_commands: input)
      expect(input.first).not_to have_key(:scope)
    end

    it "accepts nil for any scope and treats it as empty" do
      result = described_class.call(panel_commands: nil, sub_panel_commands: nil, screen_commands: [ screen_command ])
      expect(result.length).to eq(1)
      expect(result.first[:scope]).to eq(:screen)
    end

    it "preserves command payload fields (name, hint, action_name, args)" do
      command_with_args = panel_command.merge(args: { table: "x", column: 2 })
      result = described_class.call(panel_commands: [ command_with_args ])
      output = result.first
      expect(output[:name]).to eq("sync toggle")
      expect(output[:hint]).to eq("toggle panel sync")
      expect(output[:action_name]).to eq(:sync_toggle)
      expect(output[:args]).to eq(table: "x", column: 2)
    end

    it "preserves order WITHIN each scope" do
      a = { key: "a", name: "a" }
      b = { key: "b", name: "b" }
      c = { key: "c", name: "c" }
      result = described_class.call(panel_commands: [ a, b, c ])
      expect(result.map { |x| x[:key] }).to eq(%w[a b c])
    end
  end
end
