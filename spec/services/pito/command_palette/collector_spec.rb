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

    # 2026-05-24 — Bug 4 fix: palette de-duplication. The same logical
    # action (same action_name + same args) registered by two scopes
    # should appear once. First-occurrence wins so the most-specific
    # scope (sub_panel > panel > screen) shadows broader-scope duplicates.
    describe "de-duplication by [action_name, args] signature" do
      it "drops a panel command that exactly duplicates a sub_panel command's action+args" do
        sub = { key: "sync_sub", name: "sync toggle (postgres)", action_name: :sync_toggle, args: { target: "home.stack.postgres" } }
        pan = { key: "sync_pan", name: "sync toggle (postgres)", action_name: :sync_toggle, args: { target: "home.stack.postgres" } }
        result = described_class.call(sub_panel_commands: [ sub ], panel_commands: [ pan ])
        expect(result.map { |c| c[:key] }).to eq([ "sync_sub" ])
      end

      it "keeps two `sync_toggle` commands that target DIFFERENT scopes (different args)" do
        sub = { key: "sync_postgres", name: "sync toggle (postgres)", action_name: :sync_toggle, args: { target: "home.stack.postgres" } }
        pan = { key: "sync_stack",    name: "sync toggle (stack)",    action_name: :sync_toggle, args: { target: "home.stack" } }
        result = described_class.call(sub_panel_commands: [ sub ], panel_commands: [ pan ])
        expect(result.map { |c| c[:key] }).to eq(%w[sync_postgres sync_stack])
      end

      it "drops a duplicate within the same scope (keeps first)" do
        a = { key: "first",  name: "x", action_name: :foo, args: { id: 1 } }
        b = { key: "second", name: "x", action_name: :foo, args: { id: 1 } }
        result = described_class.call(panel_commands: [ a, b ])
        expect(result.map { |c| c[:key] }).to eq([ "first" ])
      end

      it "treats commands with the same path + method as duplicates" do
        a = { key: "go_a", name: "home", path: "/", method: :get }
        b = { key: "go_b", name: "home", path: "/", method: :get }
        result = described_class.call(screen_commands: [ a, b ])
        expect(result.length).to eq(1)
      end

      it "treats commands with the same path but DIFFERENT methods as distinct" do
        a = { key: "get_home",  name: "home",   path: "/", method: :get }
        b = { key: "post_home", name: "submit", path: "/", method: :post }
        result = described_class.call(screen_commands: [ a, b ])
        expect(result.length).to eq(2)
      end
    end
  end
end
