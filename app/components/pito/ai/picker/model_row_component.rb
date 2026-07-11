# frozen_string_literal: true

module Pito
  module Ai
    module Picker
      # One selectable model row in the /config ai picker — the ●-markered
      # button pito--ai-picker navigates and PATCHes. Used by the favorites,
      # recents, and per-provider sections alike (one markup, three callers).
      class ModelRowComponent < ViewComponent::Base
        # @param provider [String] registry name the row PATCHes with
        # @param id       [String] model id (the row's data-value)
        # @param active   [Boolean] wears the ● marker
        # @param favorite [Boolean] wears the ★ pin
        # @param pinned   [Boolean] shows the pinned-fallback badge
        # @param trailing [String, nil] dim right-aligned text (e.g. the
        #   provider label on favorites/recents rows)
        def initialize(provider:, id:, active: false, favorite: false, pinned: false, trailing: nil)
          @provider = provider
          @id       = id
          @active   = active
          @favorite = favorite
          @pinned   = pinned
          @trailing = trailing
        end

        attr_reader :provider, :id, :trailing

        def active?   = @active
        def favorite? = @favorite
        def pinned?   = @pinned
      end
    end
  end
end
