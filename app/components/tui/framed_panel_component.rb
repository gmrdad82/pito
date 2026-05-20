module Tui
  # Beta 4 — Phase F2. TUI framed-panel primitive. Renders a hairline
  # border (1px CSS, NOT literal box-drawing chars) around a slot of
  # content, with an optional header title separated by a
  # border-bottom. Using CSS borders keeps the panel responsive at
  # any width — the box-drawing-ASCII alternative breaks horribly
  # under reflow.
  #
  # Per ADR 0016 (TUI design system), framed panels group dense
  # sub-content inside dashboard rows / detail screens. The title
  # is plain text with weight 600 — no bracketed convention here
  # because the box itself is the affordance.
  #
  # Composition: either pass `content` directly (yields a block) or
  # set the `body` slot via `with_body { ... }`. The template
  # prefers explicit `content` over the slot when both are present.
  class FramedPanelComponent < ViewComponent::Base
    def initialize(title: nil)
      @title = title
    end

    attr_reader :title

    renders_one :body
  end
end
