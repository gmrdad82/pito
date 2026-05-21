module Tui
  # Beta 4 — Phase F1. Bottom status bar. Sticky-bottom counterpart to
  # `Tui::TopStatusBarComponent`. Provides the 3-screen nav (home /
  # videos / games), current mode lozenge, and `?` / `:` keybinding
  # hints, vim/TUI status-line style.
  #
  # Layout:
  #
  #   <mode> | home videos games | ? help  : command
  #
  # LEFT:    mode lozenge (lowercase). One of `:normal`, `:command`,
  #          `:search`. Color cycles per mode (cyan / purple / green).
  # CENTER:  3 screen links, lowercase. Current screen bolded and
  #          colored with the section accent (CSS cascade from
  #          `body[data-section]`).
  # RIGHT:   `? help` + `: command` hint markers (lowercase, muted with
  #          the key letter in foreground weight).
  #
  # C18 (2026-05-21): settings consolidated into / (home). The sections
  # list was trimmed from 8 entries to 3 (home / videos / games).
  # /settings now redirects 301 to /.
  #
  # The section accent (`--section-accent`) cascades via
  # `body[data-section]` (set by `current_section` in
  # `ApplicationHelper`), so the bar inherits the right color
  # automatically — no per-render section-to-color lookup needed.
  class BottomStatusBarComponent < ViewComponent::Base
    SECTIONS = %i[home videos games].freeze
    MODES = %i[normal command search].freeze

    def initialize(current_section:, mode: :normal)
      @current_section = current_section.to_s
      @mode = MODES.include?(mode.to_sym) ? mode.to_sym : :normal
    end

    attr_reader :current_section, :mode

    def section_classes(section)
      classes = [ "bsb-section" ]
      classes << "bsb-section--current" if section.to_s == current_section
      classes.join(" ")
    end

    def section_label(section)
      section.to_s
    end

    def section_path(section)
      case section.to_s
      when "home"   then "/"
      when "videos" then "/videos"
      when "games"  then "/games"
      else "/"
      end
    end
  end
end
