# frozen_string_literal: true

module Pito
  module Sidebar
    module GamesImport
      # Renders the IGDB game-import search sidebar body.
      #
      # Hosts a debounced search box (`pito--games-search` Stimulus controller).
      # Results are fetched from `/games/search` and rendered as a flat list of
      # clickable rows — each row may show an "In Library" badge if the game's
      # `igdb_id` is already tracked locally.
      #
      # Selecting a row dispatches `pito:import:select` with the igdb_id + title,
      # which the controller picks up and POSTs to trigger `GameImportJob`.
      #
      # Constructor:
      #   prefill          — optional String; pre-populates the search input and
      #                       triggers an immediate search on connect().
      #   conversation_uuid — the current conversation UUID, forwarded to the
      #                       import endpoint so the job can stream progress back.
      class Component < ViewComponent::Base
        # @param prefill           [String]  optional initial search term
        # @param conversation_uuid [String]  current conversation UUID
        def initialize(prefill: "", conversation_uuid:)
          @prefill           = prefill.to_s.strip
          @conversation_uuid = conversation_uuid
        end

        attr_reader :prefill, :conversation_uuid
      end
    end
  end
end
