# frozen_string_literal: true

module Videos
  # POST /videos/visit_consume
  #
  # Consumes a video-visit event after its one-time auto-click. The
  # pito--auto-visit Stimulus controller POSTs `{ event_id: }` here once it has
  # fired the click. We run the consume THROUGH the standard follow-up dispatch
  # path (FollowUpDispatchJob, :mutate mode), exactly as a `#<handle> consume`
  # reply would — the Pito::FollowUp::Handlers::VideoVisit handler flips the
  # event to its :visited (system_follow_up / surface) state, and the job
  # persists + broadcasts replace_event so the System component updates live and
  # on refresh. No echo turn is created (mutate mode), so the conversation stays
  # clean.
  #
  # Idempotent: once consumed the payload is no longer follow-up-able, so a
  # repeat POST resolves no handler and no-ops.
  class VisitsController < ApplicationController
    def consume
      event = Event.find(params[:event_id])
      FollowUpDispatchJob.perform_now(event.id, rest: "consume")
      head :ok
    end
  end
end
