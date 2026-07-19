# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/dispatch_config_injection"

# Pito::Dispatch::Availability (a tool's `enabled_if:` gate, tools.yml) and its
# two consumers:
#
#   Matrix#tool_enabled? / #available?        — the live readiness check
#   Registry#presentable_actions_for          — the PRESENTATION-ONLY filter
#     every reply palette/help surface shares (Suggestions::Engine,
#     MessageBuilder::HashtagHelp, MessageBuilder::Help::FollowUpActions)
#
# Proven GENERICALLY: a SYNTHETIC tool + a SYNTHETIC condition name (never
# "ai_configured", never "@ai") — the mechanism must gate ANY tool that
# declares `enabled_if:`, not a name it special-cases. `@ai`'s own wiring is
# covered separately in spec/lib/pito/chat/handlers/ai_spec.rb and the
# dispatch matrix specs (Matrix advertises `enabled_if: ai_configured` on
# "@ai").
RSpec.describe "tool availability (enabled_if:)" do
  describe Pito::Dispatch::Availability do
    it "lists the real 'ai_configured' condition" do
      expect(described_class.names).to include("ai_configured")
    end

    it "ready? reflects a registered predicate's current return value — never memoized" do
      flag = { ready: false }
      stub_const("Pito::Dispatch::Availability::REGISTRY",
                 described_class::REGISTRY.merge("probe" => -> { flag[:ready] }))

      expect(described_class.ready?("probe")).to be(false)
      flag[:ready] = true
      expect(described_class.ready?("probe")).to be(true)
    end

    it "fails OPEN (ready) for a blank condition name — no condition declared means nothing to gate" do
      expect(described_class.ready?(nil)).to be(true)
      expect(described_class.ready?("")).to be(true)
    end

    it "'ai_configured' delegates to Ai::Client.configured? — the single non-raising source" do
      allow(Ai::Client).to receive(:configured?).and_return(false)
      expect(described_class.ready?("ai_configured")).to be(false)

      allow(Ai::Client).to receive(:configured?).and_return(true)
      expect(described_class.ready?("ai_configured")).to be(true)
    end
  end

  # ── generic integration: a SYNTHETIC gated tool, not @ai ──────────────────
  describe "Matrix + Registry integration", type: :dispatch do
    FAKE_GATED_TOOL_YAML = <<~YAML
      fake_gated_tool:
        aliases: [fgt]
        description: pito.chat.fake_gated_tool.descriptions.fake_gated_tool
        auth: session
        enabled_if: fake_ready
        reply:
          targets:
            game_list:
              mode: append
    YAML

    before do
      @ready = false
      stub_const("Pito::Dispatch::Availability::REGISTRY",
                 Pito::Dispatch::Availability::REGISTRY.merge("fake_ready" => -> { @ready }))
      I18n.backend.store_translations(
        :en, pito: { chat: { fake_gated_tool: { descriptions: { fake_gated_tool: "Fake gated tool." } } } }
      )
      inject_dispatch_config!(verbs: FAKE_GATED_TOOL_YAML)
    end

    after { restore_dispatch_config! }

    it "Matrix#tool_enabled? is false while the condition is unready, true once it is — resolved live" do
      expect(Pito::Dispatch::Matrix.tool_enabled?("fake_gated_tool")).to be(false)
      @ready = true
      expect(Pito::Dispatch::Matrix.tool_enabled?("fake_gated_tool")).to be(true)
    end

    it "Matrix#available? gates the tool's action token on the target it declares" do
      expect(Pito::Dispatch::Matrix.available?("game_list", "fake_gated_tool")).to be(false)
      @ready = true
      expect(Pito::Dispatch::Matrix.available?("game_list", "fake_gated_tool")).to be(true)
    end

    it "Matrix#actions_for (DISPATCH) stays unfiltered — a typed reply must still reach the tool's own honest handling" do
      expect(Pito::Dispatch::Matrix.actions_for("game_list")).to include("fake_gated_tool")
      # Unaffected by @ready — dispatch never lies about what a typed reply resolves to.
    end

    it "Registry#presentable_actions_for (PRESENTATION) drops the tool while unready, offers it once ready" do
      expect(Pito::FollowUp::Registry.presentable_actions_for("game_list")).not_to include("fake_gated_tool")
      @ready = true
      expect(Pito::FollowUp::Registry.presentable_actions_for("game_list")).to include("fake_gated_tool")
    end

    it "Registry#actions_for (DISPATCH) stays unfiltered regardless of readiness" do
      expect(Pito::FollowUp::Registry.actions_for("game_list")).to include("fake_gated_tool")
      @ready = true
      expect(Pito::FollowUp::Registry.actions_for("game_list")).to include("fake_gated_tool")
    end
  end

  # ── @ai's own wiring, end to end ───────────────────────────────────────────
  describe "'@ai' (the real tool)" do
    around do |example|
      Pito::Dispatch::Matrix.reload!
      example.run
      Pito::Dispatch::Matrix.reload!
    end

    it "declares enabled_if: ai_configured" do
      expect(Pito::Dispatch::Config.tool(:"@ai")[:enabled_if]).to eq("ai_configured")
    end

    it "drops out of every rostered target's presentable actions when AI is unconfigured" do
      allow(Ai::Client).to receive(:configured?).and_return(false)

      %w[game_list video_list channel_list game_detail video_detail channel_detail
         channel_games game_channels game_similar game_linked_videos
         analyze_message analytics_glance ai_message].each do |target|
        expect(Pito::FollowUp::Registry.presentable_actions_for(target)).not_to include("@ai"),
          "expected '@ai' absent from presentable_actions_for(#{target.inspect}) when unconfigured"
      end
    end

    it "is offered on every rostered target's presentable actions once AI is configured" do
      allow(Ai::Client).to receive(:configured?).and_return(true)

      %w[game_list video_list channel_list game_detail video_detail channel_detail
         channel_games game_channels game_similar game_linked_videos
         analyze_message analytics_glance ai_message].each do |target|
        expect(Pito::FollowUp::Registry.presentable_actions_for(target)).to include("@ai"),
          "expected '@ai' present in presentable_actions_for(#{target.inspect}) when configured"
      end
    end

    it "stays in Matrix#actions_for (DISPATCH) regardless of configured state — typed dispatch stays honest" do
      allow(Ai::Client).to receive(:configured?).and_return(false)
      expect(Pito::Dispatch::Matrix.actions_for("game_list")).to include("@ai")
    end
  end
end
