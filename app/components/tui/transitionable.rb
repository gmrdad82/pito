module Tui
  # Tui::Transitionable — ViewComponent mixin. Include in any VC that needs
  # to opt into the canonical transition system (scramble-settle +
  # color-crossfade + shimmer). Returns a Hash of data-attrs to spread into
  # a content_tag.
  #
  # Example:
  #
  #   class Tui::SomeMetricComponent < ViewComponent::Base
  #     include Tui::Transitionable
  #
  #     def call
  #       content_tag :span, @value,
  #         class: "tui-some-metric",
  #         **transitionable_attrs(value: @value, color: :muted, active_color: :busy)
  #     end
  #   end
  #
  # The mixin emits ONLY the data-attrs. CSS classes (e.g. .tui-sync-word,
  # .tui-sidekiq-cell) are the caller's responsibility — they hint the
  # controller's `detectKind()` and own the per-kind palette.
  #
  # Returned shape:
  #
  #   {
  #     data: {
  #       controller: "tui-transition",
  #       tui_transition_effect_value: "scramble-settle",
  #       tui_transition_value_value:  "synced",
  #       tui_transition_align_value:  "left",
  #       tui_transition_shimmer_value: "no",
  #       ... (color / active_color / duration / stagger / debounce / prefix
  #            only when explicitly provided)
  #     }
  #   }
  #
  # @contract see docs/design.md § Transitions
  # @contract see docs/architecture.md § Pito::Transitions
  module Transitionable
    # Build the data-attrs hash for a tui-transition host element.
    #
    # @param value [#to_s] the target value to display
    # @param effect [Symbol] :scramble_settle (default) — currently only effect
    # @param color [Symbol, nil] base color name (:muted/:accent/:busy/...)
    # @param active_color [Symbol, nil] when value > 0, this color is used
    # @param shimmer [Boolean] sync-only decoration
    # @param align [Symbol] :left, :center, :right
    # @param duration [Integer, nil] override default scramble duration (ms)
    # @param stagger [Integer, nil] override default stagger (ms)
    # @param debounce [Integer, nil] override default debounce (ms)
    # @param prefix [String, nil] static prefix (e.g. "b" for sidekiq busy cell)
    # @return [Hash{Symbol => Object}] spread into content_tag's data: { ... }
    def transitionable_attrs(value:, effect: :scramble_settle, color: nil, active_color: nil,
                             shimmer: false, align: :left, duration: nil, stagger: nil,
                             debounce: nil, prefix: nil)
      attrs = {
        controller: "tui-transition",
        tui_transition_effect_value: effect.to_s.tr("_", "-"),
        tui_transition_value_value: value.to_s,
        tui_transition_align_value: align.to_s,
        tui_transition_shimmer_value: shimmer ? "yes" : "no"
      }
      attrs[:tui_transition_color_value]        = color.to_s        if color
      attrs[:tui_transition_active_color_value] = active_color.to_s if active_color
      attrs[:tui_transition_duration_value]     = duration          if duration
      attrs[:tui_transition_stagger_value]      = stagger           if stagger
      attrs[:tui_transition_debounce_value]     = debounce          if debounce
      attrs[:tui_transition_prefix_value]       = prefix            if prefix
      { data: attrs }
    end
  end
end
