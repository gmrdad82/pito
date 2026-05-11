# Phase 23 §23b — shared ViewComponent for the per-field decision
# radio group on the diff page.
#
# Renders two radios per field row — `accept pito` / `accept youtube`
# — with bracketed labels matching the project's visual convention.
# Default selection is `accept youtube` (locked Q6 — preserves
# YouTube-as-source-of-truth).
#
# When `disabled:` is true (the field is display-only — counts,
# duration, thumbnail), the `accept pito` radio is disabled and the
# `accept youtube` radio is checked + disabled with a note "(display-
# only)" — the field is in the diff for visibility but the user has
# no agency to push back.
#
# This component is shared with the channel diff (Phase 11 §11i) when
# that ships; the channel diff view will pass the same locals.
class DiffDecisionRadioComponent < ViewComponent::Base
  PITO    = "pito".freeze
  YOUTUBE = "youtube".freeze

  def initialize(field:, name: "decisions", disabled: false, selected: YOUTUBE)
    @field = field.to_s
    @name = name
    @disabled = disabled
    @selected = selected.to_s
  end

  attr_reader :field, :disabled

  def input_name
    "#{@name}[#{@field}]"
  end

  def input_id(value)
    "decision_#{@field}_#{value}"
  end

  def pito_checked?
    !@disabled && @selected == PITO
  end

  def youtube_checked?
    @disabled || @selected == YOUTUBE
  end

  def pito_disabled?
    @disabled
  end

  def youtube_disabled?
    false
  end
end
