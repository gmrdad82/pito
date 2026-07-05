# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class AuthComponent < ViewComponent::Base
        # The @suffix span's stable id (G87) — the mini status' dedicated
        # app-version slot, updated by pito--version-watch on every cable
        # version heartbeat.
        VERSION_SLOT_ID = "pito-mini-status-version"

        def initialize(state: false)
          @state = state
        end

        def label
          if @state
            t("pito.shell.mini_status.authenticated", nickname: AppSetting.nickname)
          else
            t("pito.shell.mini_status.anonymous")
          end
        end

        # Authenticated wears the green↔yellow "me" shimmer (G70); anonymous
        # stays flat red.
        def css_class = @state ? "pito-me-shimmer" : "text-red"

        # The muted `@suffix` after the nickname (image tag in prod, host in dev) —
        # only when authenticated. nil → no suffix rendered.
        def version_suffix = @state ? Pito::Version.suffix : nil
      end
    end
  end
end
