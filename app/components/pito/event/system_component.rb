# frozen_string_literal: true

module Pito
  module Event
    # System — default backend response. Surface-colored left bar, no background.
    # First segment emitted per turn. Supports expandable overflow (e.g. /help).
    class SystemComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload       = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload      = payload
        @body         = payload[:body].presence || resolve_text(payload)
        @expand_lines = Array(payload[:expand_lines]).map(&:to_s)
        @expand_detail = Array(payload[:expand_detail]).map(&:to_s)
        @expand_more_count = payload[:expand_more_count].to_i
        @handle       = payload[:handle].to_s.presence
        @authenticated = payload.fetch(:authenticated, true)
        @timestamp    = event&.created_at
      end

      attr_reader :body, :expand_lines, :expand_detail, :expand_more_count, :handle

      def expandable?   = @expand_detail.any?
      def authenticated? = @authenticated
      def accent        = :surface
      def background    = nil

      private

      def resolve_text(payload)
        if payload[:message_key]
          I18n.t(payload[:message_key], **payload.fetch(:message_args, {}))
        else
          payload[:text]
        end
      end
    end
  end
end
