# frozen_string_literal: true

module Pito
  module Grammar
    Spec = Data.define(:namespace, :name, :aliases, :slots, :description_key, :auth) do
      def initialize(namespace:, name:, aliases: [], slots: [], description_key: nil, auth: :any)
        super
      end

      # namespace       — Symbol, one of :slash, :chat, :hashtag
      # name            — Symbol, the canonical command/tool name (e.g. :config, :list, :add)
      # aliases         — Array of Symbol alternate names (defaults to [])
      # slots           — Array of Pito::Grammar::Slot (defaults to [])
      # description_key — String i18n key for help/autocomplete copy (nilable)
      # auth            — Symbol, one of :any, :unauthenticated_only, :authenticated_only
      #                   (default :any)

      def names
        [ name, *aliases ]
      end

      def slot(slot_name)
        slots.find { |s| s.name == slot_name }
      end
    end
  end
end
