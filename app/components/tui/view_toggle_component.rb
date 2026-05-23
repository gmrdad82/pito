module Tui
  # Tui::ViewToggleComponent — width-stable pair of mutually-exclusive view
  # toggle actions. The active view renders with surrounding spaces and a
  # distinct color (e.g. " schedule "); the inactive view renders with
  # brackets and the standard section-accent action color (e.g.
  # "[month]"). Both renderings are the same character width so the
  # surrounding panel chrome doesn't shift horizontally on toggle.
  #
  # ## Width invariance
  #
  # The inactive renderer adds `[` + `]` around the label (2 chars).
  # The active renderer adds ` ` + ` ` around the label (2 chars).
  # Both renderings therefore occupy `label.length + 2` columns.
  # Combined with `white-space: pre` on the rendered span the leading
  # and trailing whitespace is preserved verbatim — no collapse.
  #
  # ## Colors
  #
  # - INACTIVE: section-accent (via `--section-accent`) — matches the
  #   `[reindex]` bracketed-action family on the same panel.
  # - ACTIVE: chosen via `active_color:` kwarg, defaults to `:success`
  #   (Dracula green `#50fa7b`). The user-locked design explicitly
  #   noted accent collides with the inactive action color and asked
  #   for a distinct one — green reads as "this is the current view".
  #
  # ## Kwargs
  #
  # @param views [Array<Hash>] each entry has keys:
  #   - `:name` (Symbol) — canonical view name
  #   - `:label` (String) — visible text (lowercased per design.md)
  # @param current [Symbol] currently-active view name
  # @param event_name [String] CustomEvent name dispatched on the
  #   root element when the user activates a different view (parent
  #   panel listens and re-renders its body).
  # @param active_color [Symbol] visual variant for the active view —
  #   `:success` (default) / `:warn` / `:danger` / `:accent_pale`.
  #
  # ## TUI parity
  #
  # The Ratatui sibling implements the same pattern via `Spans` with
  # different `Style` modifiers + literal space/bracket characters.
  # Width-stability keeps the Rust grid layout still on toggle too.
  class ViewToggleComponent < ViewComponent::Base
    ALLOWED_ACTIVE_COLORS = %i[success warn danger accent_pale].freeze

    def initialize(views:, current:, event_name: "tui:view-toggle-changed", active_color: :success)
      @views = views
      @current = current.to_sym
      @event_name = event_name
      @active_color = active_color.to_sym
      unless ALLOWED_ACTIVE_COLORS.include?(@active_color)
        raise ArgumentError, "Tui::ViewToggleComponent active_color must be one of #{ALLOWED_ACTIVE_COLORS.inspect}, got #{@active_color.inspect}"
      end
    end

    attr_reader :event_name

    def renderables
      @views.map { |v| renderable_for(v) }
    end

    def root_data
      {
        controller: "tui-view-toggle",
        "tui-view-toggle-current-value": @current.to_s,
        "tui-view-toggle-event-name-value": @event_name
      }
    end

    private

    def renderable_for(view)
      name = view.fetch(:name).to_sym
      label = view.fetch(:label)
      active = (name == @current)
      {
        name: name,
        label: label,
        active: active,
        visible_text: active ? " #{label} " : "[#{label}]",
        classes: classes_for(active)
      }
    end

    def classes_for(active)
      base = "tui-view-toggle__view"
      if active
        "#{base} #{base}--active is-#{@active_color.to_s.dasherize}"
      else
        "#{base} #{base}--inactive"
      end
    end
  end
end
