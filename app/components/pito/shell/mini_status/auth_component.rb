# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class AuthComponent < ViewComponent::Base
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

        def css_class = @state ? "text-green" : "text-red"

        # The muted `@suffix` after the nickname (image tag in prod, host in dev) —
        # only when authenticated. nil → no suffix rendered.
        def version_suffix = @state ? Pito::Version.suffix : nil
      end
    end
  end
end
