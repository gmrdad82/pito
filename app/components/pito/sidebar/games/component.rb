# frozen_string_literal: true

module Pito
  module Sidebar
    module Games
      # Renders the game picker list for the sidebar.
      #
      # Displays a flat list of games (id + title), keyboard-highlightable rows.
      # The outer container mounts `data-controller="pito--games-nav"` so the
      # Stimulus controller can attach keyboard navigation.
      #
      # Two picker modes are supported, passed as a data attribute to the controller:
      #   "show"   → Enter fills `show game <id>` in the chatbox + submits
      #   "delete" → Enter fills `rm game <id>` in the chatbox + submits
      #
      # Constructor:
      #   games  — ActiveRecord relation or Array of Game records (responds to
      #            #id and #title).
      #   mode   — Symbol :show or :delete (default :show); controls the command
      #            the picker builds on selection.
      class Component < ViewComponent::Base
        # @param games [Array<Game>]
        # @param mode  [Symbol] :show or :delete
        def initialize(games:, mode: :show)
          @games = games
          @mode  = mode.to_s
        end

        def empty?
          @games.empty?
        end

        def empty_state_text
          Pito::Copy.render("pito.copy.games.picker_empty")
        end

        attr_reader :games, :mode
      end
    end
  end
end
