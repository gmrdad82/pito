# frozen_string_literal: true

module Pito
  module Shell
    # Supplies the chatbox placeholder hint.
    #
    # Unauthenticated visitors always get the login example — nothing else
    # works until they log in. Authenticated users get a random example
    # sampled from the implemented commands/messages.
    #
    # BOILERPLATE: `AUTHENTICATED_HINTS` is the extension point. As commands land,
    # add their i18n hint key here and the copy under `pito.shell.chatbox.hints.*`.
    # Today only `/help` is implemented, and since every conversation is currently
    # unauthenticated the authenticated branch is effectively dormant.
    module ChatboxHint
      module_function

      AUTHENTICATED_HINTS = %i[help].freeze

      def sample(authenticated:)
        key = authenticated ? AUTHENTICATED_HINTS.sample : :login
        I18n.t("pito.shell.chatbox.hints.#{key}")
      end
    end
  end
end
