class ReindexAllJob < ApplicationJob
  # Phase 32 follow-up (2026-05-16). Three-layer reindex lock + live UI.
  #
  # Layer 1 — DB flag (`AppSetting.reindex_running` + `reindex_started_at`).
  #           The controller (`SettingsController#reindex`) consults the
  #           flag BEFORE enqueueing; the ensure block below clears it
  #           so a worker crash never leaves it stuck.
  # Layer 2 — Sidekiq uniqueness (the `sidekiq_options` line below).
  #           Sidekiq OSS does not have built-in unique jobs (this is a
  #           Sidekiq Enterprise / `sidekiq-unique-jobs` feature). The
  #           options are recorded here as a no-op intent declaration —
  #           the DB flag is the real safety net in OSS land. If pito
  #           ever adopts `sidekiq-unique-jobs`, the keys are already
  #           in place and the gem starts enforcing them.
  # Layer 3 — UI gate (Stack pane Voyage section renders `dot-loader`
  #           while the flag is true, the `[reindex]` link otherwise).
  #           The broadcast in `ensure` swaps every open `/settings`
  #           tab back to the idle state without a page refresh.
  #
  # `RESINDEX_SLEEP_SECONDS` is a deliberate testing-visibility pause —
  # it gives the operator (and any pair-coding LLM) time to SEE the
  # in-progress UI state before the job clears the flag. Dial down to
  # `0` before any production use; leaving it at `8` in production
  # would needlessly stall the queue.
  REINDEX_SLEEP_SECONDS = 8

  queue_as :search
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    # FOR LOCAL TESTING VISIBILITY — remove or set REINDEX_SLEEP_SECONDS
    # to 0 before production use. See the constant comment above.
    sleep REINDEX_SLEEP_SECONDS if REINDEX_SLEEP_SECONDS.positive?

    engine = Search.engine
    [ Channel, Video ].each do |model|
      engine.reindex_all(model)
    end
  ensure
    # Always clear the flag, even on crash, to keep the UI honest and
    # prevent a stuck-flag deadlock. The broadcast lands AFTER the
    # clear so any subscribed `/settings` tab swaps to the idle state.
    AppSetting.clear_reindex_lock!
    broadcast_voyage_section
  end

  private

  # Re-render the Voyage section partial and replace the
  # `voyage_section` target in every `/settings` tab subscribed to
  # `reindex_status`. The partial reads `AppSetting.reindex_running?`
  # fresh, so post-clear it lands in the idle `[reindex]` state.
  def broadcast_voyage_section
    Turbo::StreamsChannel.broadcast_replace_to(
      "reindex_status",
      target: "voyage_section",
      partial: "settings/voyage_section"
    )
  rescue StandardError
    # The broadcast is a UX nicety; a Redis hiccup or Turbo wire
    # failure should not raise out of the job's ensure block.
    nil
  end
end
