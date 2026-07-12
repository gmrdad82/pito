# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class AuthComponent < ViewComponent::Base
        # The @suffix span's stable id — the mini status' dedicated
        # app-version slot, updated by pito--version-watch on every cable
        # version heartbeat.
        VERSION_SLOT_ID = "pito-mini-status-version"

        def initialize(state: false)
          @state = state
        end

        def label
          if @state
            # The tag IS the identity now (owner fat-cut: the nickname/"me"
            # concept is gone): "dev" outside production, the image tag in
            # prod ("pito" only when the build carries no meaningful tag).
            t("pito.shell.mini_status.authenticated", tag: Pito::Version.suffix.presence || "pito")
          else
            t("pito.shell.mini_status.anonymous")
          end
        end

        # One trailing tone across the bar (owner): tag, count, "commands"
        # all wear the dim token; anonymous stays red.
        def css_class = @state ? "text-fg-dim" : "text-red"
      end
    end
  end
end
