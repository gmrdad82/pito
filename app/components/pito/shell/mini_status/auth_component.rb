# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class AuthComponent < ViewComponent::Base
        def initialize(state: false)
          @state = state
        end
        def label = @state ? t("pito.shell.mini_status.authenticated") : t("pito.shell.mini_status.anonymous")
        def css_class = @state ? "text-green" : "text-red"
      end
    end
  end
end
