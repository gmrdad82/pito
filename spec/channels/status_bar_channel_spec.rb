require "rails_helper"

# Beta 4 — Phase F1 Lane A. Locks the contract of the global status-bar
# cable channel.
#
# * Authenticated users SUBSCRIBE and stream from `pito:status_bar`.
# * Unauthenticated cable identities (no `current_user`) are REJECTED
#   at the channel layer — belt-and-braces beside the connection-level
#   `reject_unauthorized_connection` in `ApplicationCable::Connection`.
# * Broadcasts on `pito:status_bar` reach every subscribed user (one
#   global broadcasting; pito is single-install multi-user — ADR 0003).
RSpec.describe StatusBarChannel, type: :channel do
  describe "#subscribed" do
    context "with an authenticated user" do
      let(:user) { create(:user) }

      before { stub_connection(current_user: user) }

      it "confirms the subscription" do
        subscribe

        expect(subscription).to be_confirmed
      end

      it "streams from `pito:status_bar`" do
        subscribe

        expect(subscription).to have_stream_from("pito:status_bar")
      end

      it "does not transmit an initial payload on subscribe" do
        # The producer side (Sidekiq middleware) drives all broadcasts;
        # the channel itself never emits an on-subscribe snapshot. If a
        # future change pushes an initial payload, this test
        # intentionally breaks so the contract gets re-locked.
        subscribe

        expect(transmissions).to be_empty
      end
    end

    context "without an authenticated user" do
      before { stub_connection(current_user: nil) }

      it "rejects the subscription" do
        subscribe

        expect(subscription).to be_rejected
      end
    end
  end

  describe "broadcast delivery" do
    let(:user) { create(:user) }

    before { stub_connection(current_user: user) }

    it "forwards a payload broadcast on the stream to the subscriber" do
      subscribe
      payload = { "kind" => "data", "payload" => { "busy" => 1, "enqueued" => 2 } }

      expect {
        ActionCable.server.broadcast("pito:status_bar", payload)
      }.to have_broadcasted_to("pito:status_bar").with(payload)
    end
  end
end
