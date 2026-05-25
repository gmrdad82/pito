module Tui
  # Tui::TotpCodeComponent — segmented code input (TOTP digits or backup code).
  #
  # Purpose:
  #   Single source of truth for the segmented-box auth code input. Replaces
  #   `TotpCodeInputComponent` (6-digit) and `Pito::BackupCodeInputComponent`
  #   (8-char alphanumeric) — both deleted in favour of this unified component
  #   whose `mode:` kwarg picks the correct variant.
  #
  #   Renders N discrete `<input>` boxes + a hidden aggregation field. The
  #   Stimulus controller `tui-totp-code` (tui_totp_code_controller.js) wires
  #   per-box input, keydown, paste, and blur handlers for each mode.
  #
  # Kwargs:
  #   field:     — form-param name on the hidden aggregation field. Defaults
  #                to `:code` (`:digits` mode) / `:backup_code` (`:backup` mode).
  #   mode:      — :digits (6 numeric boxes, default) or :backup (8 alphanumeric).
  #   autofocus: — Boolean. First box gets autofocus when true. Defaults to false.
  #   hidden:    — Boolean. Wraps the component in `hidden` so Stimulus can
  #                toggle visibility. Defaults to false.
  #   data:      — Hash of extra data-* attrs placed on the outer wrapper
  #                (e.g. { pito_auth_dialog_target: "totpField" }).
  #
  # Variants:
  #   :digits  — 6 numeric single-digit boxes. Accepts only 0–9. Auto-submits
  #              the parent form when all 6 cells are filled.
  #   :backup  — 8 alphanumeric boxes. Accepts a–z, A–Z, 0–9. Lowercases
  #              on entry. Does NOT auto-submit.
  #
  # Stimulus controller: tui-totp-code (app/javascript/controllers/tui_totp_code_controller.js)
  #
  # Related:
  #   Pito::AuthDialogComponent — primary consumer
  #   app/javascript/controllers/tui_totp_code_controller.js
  class TotpCodeComponent < ViewComponent::Base
    DIGIT_CONFIG  = { count: 6, inputmode: "numeric", pattern: '\d{1}',
                      controller_target: "digit", default_field: "code" }.freeze
    BACKUP_CONFIG = { count: 8, inputmode: "text",    pattern: nil,
                      controller_target: "char",  default_field: "backup_code" }.freeze

    def initialize(field: nil, mode: :digits, autofocus: false, hidden: false, data: {})
      @mode      = mode == :backup ? :backup : :digits
      @config    = @mode == :backup ? BACKUP_CONFIG : DIGIT_CONFIG
      @field     = (field || @config[:default_field]).to_s
      @autofocus = autofocus
      @hidden    = hidden
      @data      = data || {}
    end

    attr_reader :field, :data

    def mode_digits?
      @mode == :digits
    end

    def autofocus?
      @autofocus
    end

    def hidden?
      @hidden
    end

    def box_count
      @config[:count]
    end

    def inputmode
      @config[:inputmode]
    end

    def pattern
      @config[:pattern]
    end

    def controller_target
      @config[:controller_target]
    end

    # The Stimulus controller name used on the wrapper element.
    def stimulus_controller
      "tui-totp-code"
    end

    # Wrapper data attrs: controller identifier + the outer data hash merged in.
    # The controller's `mode` value tells JS which sanitize / auto-submit path to use.
    def wrapper_data
      {
        controller: stimulus_controller,
        "tui-totp-code-mode-value": @mode.to_s,
        "tui-totp-code-field-value": @field
      }.merge(@data)
    end
  end
end
