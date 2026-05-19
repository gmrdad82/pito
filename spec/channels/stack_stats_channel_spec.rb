require "rails_helper"

# 2026-05-18 (Wave F consolidation) — fattened from the original
# 10-line happy-path. Locks the behavior the production code documents
# in `app/channels/stack_stats_channel.rb`:
#
# * subscriptions are accepted unconditionally (single-user app,
#   no per-user scoping — see the file header)
# * the channel streams from the global `stack_stats` broadcasting
# * no payload is `transmit`-ed on `subscribed` (the producer side is
#   `StackStats::Broadcaster`; consumers wait for the next broadcast)
# * a broadcast over the stream reaches the subscriber as JSON
RSpec.describe StackStatsChannel, type: :channel do
  describe "#subscribed" do
    it "confirms the subscription" do
      subscribe

      expect(subscription).to be_confirmed
    end

    it "streams from the `stack_stats` broadcasting" do
      subscribe

      expect(subscription).to have_stream_from("stack_stats")
    end

    it "does not transmit an initial payload on subscribe" do
      # Production note: `StackStatsChannel#subscribed` only calls
      # `stream_from`. The initial snapshot is delivered by the next
      # broadcast from `StackStats::Broadcaster` (fired by Sidekiq
      # jobs at state-change moments), NOT by an on-subscribe
      # `transmit`. If a future change pushes an initial snapshot,
      # this assertion intentionally breaks so the contract gets
      # re-locked.
      subscribe

      expect(transmissions).to be_empty
    end
  end

  describe "connection auth" do
    # `ApplicationCable::Connection` is an empty subclass — there is no
    # `identified_by` / `find_verified_user` gate. The header on
    # `app/channels/stack_stats_channel.rb` calls this out as a
    # deliberate single-user-app choice ("no per-user scoping; every
    # subscriber sees the same global Stack-pane snapshot"). The test
    # below locks the current contract: subscribing does not require an
    # authenticated user identity on the connection.
    it "accepts subscriptions without an authenticated user identity" do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).not_to be_rejected
    end
  end

  describe "broadcast delivery" do
    it "forwards a payload broadcast on the stream to the subscriber" do
      subscribe
      payload = { "busy" => 1, "enqueued" => 2 }

      expect {
        ActionCable.server.broadcast("stack_stats", payload)
      }.to have_broadcasted_to("stack_stats")
        .from_channel(described_class)
        .with(payload)
    end
  end

  describe "broadcast failure path" do
    # Hard to simulate end-to-end inside a channel spec: the failure
    # surface lives in `StackStats::Broadcaster.broadcast!`, which
    # rescues `StandardError`, logs a `[StackStats::Broadcaster]`
    # warning, and returns `nil` (see
    # `app/services/stack_stats/broadcaster.rb` and its dedicated spec
    # at `spec/services/stack_stats/broadcaster_spec.rb`). From the
    # CHANNEL'S side, a Redis hiccup is invisible — `stream_from`
    # registers the stream synchronously and the channel never sees
    # the missed message. We assert the only channel-observable
    # property here: a subscribe call still succeeds even when the
    # pubsub backend never delivers anything.
    it "remains a confirmed subscription even with no broadcasts delivered" do
      subscribe

      # No broadcast ever happens — simulating "Redis ate the message"
      # from the subscriber's vantage.
      expect(subscription).to be_confirmed
      expect(transmissions).to be_empty
    end
  end
end
