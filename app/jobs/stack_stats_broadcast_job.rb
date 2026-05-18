# 2026-05-18 (DR follow-up #2) — Delayed Stack-pane broadcast.
#
# Companion to `StackStats::Broadcaster.broadcast!`. The immediate
# broadcast invoked from a worker's `ensure` block captures the post-
# work DB state (Voyage embeddings, Meilisearch document counts) but
# CANNOT capture the post-work Sidekiq queue counters: the current
# worker thread has not yet decremented its `busy` slot — that
# release happens AFTER `ensure` returns and Sidekiq notices the
# job finished.
#
# The result, before this job existed: a `[reindex]` click would
# correctly update the Voyage section to 13/13 + 18/18, but the
# Redis pane would freeze at `busy=3` (the still-in-flight worker
# counted itself) and never recover, because no further broadcast
# fired after the worker actually released its slot.
#
# Pattern: every job that calls `StackStats::Broadcaster.broadcast!`
# in its `ensure` block ALSO enqueues this job with `set(wait: 1.second)`.
# The follow-up runs in a fresh worker context AFTER the original
# worker decremented its `busy` counter, so its snapshot of
# `Sidekiq::Workers.new.size` reflects reality.
#
# This job does NOT re-enqueue itself on completion (it would loop
# forever). It is a one-shot trailing-edge broadcast. If multiple
# jobs finish in the same second, multiple delayed broadcasts queue
# up — each is cheap (one cable publish) and they coalesce visually
# on the client because they carry the same shape.
class StackStatsBroadcastJob < ApplicationJob
  queue_as :default

  def perform
    StackStats::Broadcaster.broadcast!
  end
end
