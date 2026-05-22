# frozen_string_literal: true

require "rails_helper"

# Pito::Transitions JS parity spec.
#
# Locks the canonical contract between the Ruby effects registry +
# the JS Stimulus controller's static values. Failing this spec means
# the two have drifted and a new effect was added on one side but not
# the other.
#
# The Ruby side cannot execute the JS controller — so we lock the
# contract via static analysis of the JS source. Anyone renaming
# Stimulus values, kind names, or effect names on EITHER side will
# trip this spec at test time.
#
# @contract see app/services/pito/transitions/effects.rb
# @contract see app/javascript/controllers/tui_transition_controller.js
# @contract see app/components/tui/transitionable.rb
RSpec.describe "Pito::Transitions JS parity" do
  let(:js_path) { Rails.root.join("app/javascript/controllers/tui_transition_controller.js") }
  let(:js_source) { js_path.read }

  describe "Stimulus value declarations on tui-transition" do
    # The Ruby Tui::Transitionable mixin emits the following data-attrs
    # (camelCased to Stimulus value names): value / color / activeColor /
    # shimmer / align / duration / stagger / debounce / prefix / effect.
    # All 10 MUST be declared as Stimulus values on the JS controller —
    # an undeclared attr is silently ignored at runtime and breaks the
    # contract.
    %w[value color activeColor shimmer align duration stagger debounce prefix effect].each do |attr|
      it "declares Stimulus value `#{attr}`" do
        expect(js_source).to match(/^\s*#{Regexp.escape(attr)}:\s/),
          "expected JS controller to declare Stimulus value `#{attr}` but didn't"
      end
    end
  end

  describe "detectKind() kind names" do
    # The 5 canonical kinds, one per CSS-class hook, drive `detectKind`'s
    # branch. Each branch returns a string the rest of the controller
    # uses to look up colors / scramble pools.
    %w[sync datetime sidekiq breadcrumb mode].each do |kind|
      it "maps a class-hook to kind `#{kind}`" do
        expect(js_source).to include(%(return "#{kind}")),
          "expected JS detectKind to return `#{kind}`"
      end
    end
  end

  describe "segments Stimulus value and pass-through regex extensions" do
    it "JS controller declares the segments Stimulus value for per-segment color regions" do
      expect(js_source).to include("segments:"),
        "expected JS controller to declare Stimulus value `segments`"
    end

    it "JS controller's scramble-settle pass-through regex includes comma and middle dot" do
      expect(js_source).to match(/\/\[.*[,·].*\]\/\.test/),
        "expected the pass-through regex to include comma and middle dot"
    end
  end

  describe "Ruby Effects registry ↔ JS effect-name parity" do
    it "Pito::Transitions::Effects exposes the 3 canonical effect names" do
      # If a 4th effect lands on either side, this assertion forces the
      # other side to add it too.
      expect(Pito::Transitions::Effects.all_names).to eq(
        %i[scramble_settle color_crossfade shimmer]
      )
    end

    it "JS controller's default `effect` value is the canonical scramble-settle" do
      # The Ruby snake_case (:scramble_settle) maps to dash-case on the
      # data-attr (scramble-settle). The default in the JS controller is
      # the same canonical name.
      expect(js_source).to match(/effect:\s+\{\s*type:\s+String,\s+default:\s+"scramble-settle"\s*\}/)
    end

    it "JS controller comment-documents all 3 effect names" do
      # Each effect is documented in the JS header comment. The presence
      # of all 3 dash-case names ensures the JS layer at least knows
      # about every Ruby-registered effect.
      Pito::Transitions::Effects.all_names.each do |effect_name|
        dash_case = effect_name.to_s.tr("_", "-")
        expect(js_source).to include(dash_case),
          "expected JS controller header to mention effect `#{dash_case}`"
      end
    end
  end
end
