require "rails_helper"

RSpec.describe Tui::Transitionable do
  let(:dummy_class) { Class.new { include Tui::Transitionable } }
  let(:instance)    { dummy_class.new }

  describe "#transitionable_attrs" do
    it "emits the canonical controller name" do
      attrs = instance.transitionable_attrs(value: "x")
      expect(attrs[:data][:controller]).to eq("tui-transition")
    end

    it "emits effect value with dash-cased default" do
      attrs = instance.transitionable_attrs(value: "x")
      expect(attrs[:data][:tui_transition_effect_value]).to eq("scramble-settle")
    end

    it "passes value through as string" do
      expect(instance.transitionable_attrs(value: 42)[:data][:tui_transition_value_value]).to eq("42")
    end

    it "defaults align to left" do
      expect(instance.transitionable_attrs(value: "x")[:data][:tui_transition_align_value]).to eq("left")
    end

    it "honors align: :right" do
      expect(instance.transitionable_attrs(value: "x", align: :right)[:data][:tui_transition_align_value]).to eq("right")
    end

    it "defaults shimmer to no" do
      expect(instance.transitionable_attrs(value: "x")[:data][:tui_transition_shimmer_value]).to eq("no")
    end

    it "encodes shimmer: true as 'yes'" do
      expect(instance.transitionable_attrs(value: "x", shimmer: true)[:data][:tui_transition_shimmer_value]).to eq("yes")
    end

    it "emits color attr only when color is provided" do
      attrs = instance.transitionable_attrs(value: "x", color: :muted)
      expect(attrs[:data][:tui_transition_color_value]).to eq("muted")
    end

    it "omits color attr when color is nil" do
      expect(instance.transitionable_attrs(value: "x")[:data].key?(:tui_transition_color_value)).to be(false)
    end

    it "emits active_color when provided" do
      attrs = instance.transitionable_attrs(value: "x", active_color: :busy)
      expect(attrs[:data][:tui_transition_active_color_value]).to eq("busy")
    end

    it "emits prefix when provided" do
      attrs = instance.transitionable_attrs(value: "0", prefix: "b")
      expect(attrs[:data][:tui_transition_prefix_value]).to eq("b")
    end

    it "emits duration/stagger/debounce overrides only when provided" do
      attrs = instance.transitionable_attrs(value: "x", duration: 500, stagger: 50)
      expect(attrs[:data][:tui_transition_duration_value]).to eq(500)
      expect(attrs[:data][:tui_transition_stagger_value]).to eq(50)
      expect(attrs[:data].key?(:tui_transition_debounce_value)).to be(false)
    end

    it "translates underscored effect symbols to dash-case" do
      attrs = instance.transitionable_attrs(value: "x", effect: :color_crossfade)
      expect(attrs[:data][:tui_transition_effect_value]).to eq("color-crossfade")
    end

    it "encodes color symbol via to_s" do
      attrs = instance.transitionable_attrs(value: "x", color: :accent)
      expect(attrs[:data][:tui_transition_color_value]).to eq("accent")
    end

    it "omits prefix when nil" do
      attrs = instance.transitionable_attrs(value: "x")
      expect(attrs[:data].key?(:tui_transition_prefix_value)).to be(false)
    end
  end
end
