# frozen_string_literal: true

module Games
  # POST /games/import
  #
  # Enqueues `GameImportJob` for the given IGDB game.  The job orchestrates
  # the 5-step progress stream back to the conversation.
  #
  # Request body (JSON):
  #   { "igdb_id": 1234, "title": "Hollow Knight", "uuid": "<conversation_uuid>" }
  #
  # Response:
  #   204 No Content on success
  #   401 Unauthorized when not authenticated
  #   422 Unprocessable Entity when igdb_id or uuid is missing/invalid
  #
  # Auth: authenticated_only (unauthenticated → 401).
  class ImportController < ApplicationController
    # Auth: handled by Sessions::AuthConcern. No allow_anonymous → authenticated only.

    def create
      igdb_id  = Integer(params[:igdb_id])
      title    = params[:title].to_s.strip
      uuid     = params[:uuid].to_s.strip

      conversation = Conversation.find_by(uuid: uuid)
      return head :unprocessable_entity if conversation.nil?

      GameImportJob.perform_later(
        igdb_id:,
        title:,
        conversation_id: conversation.id
      )

      head :no_content
    rescue ArgumentError, TypeError
      head :unprocessable_entity
    end
  end
end
