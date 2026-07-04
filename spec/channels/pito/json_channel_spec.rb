# frozen_string_literal: true

require "rails_helper"

# Pito::JsonChannel — the cable side of the non-browser client surface.
# Subscription is gated by AUTH (not by a signed stream name): guests and
# unknown conversations are rejected outright, so the cable is no leakier
# than the HTML page (which withholds the scrollback from anonymous visitors).

RSpec.describe Pito::JsonChannel, type: :channel do
  let!(:conversation) { Conversation.create! }

  # ConnectionStub only carries the declared identifiers — graft the
  # Connection#authenticated? predicate the channel consults.
  def stub_conn(session_id:, authenticated:)
    stub_connection(session_id:).tap do |conn|
      conn.define_singleton_method(:authenticated?) { authenticated }
    end
  end

  it "confirms and streams the conversation's JSON mirror for an authenticated session" do
    stub_conn(session_id: "sid-123", authenticated: true)

    subscribe uuid: conversation.uuid

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("pito:json:conversation:#{conversation.uuid}")
  end

  it "rejects guests — the cable must be no leakier than the page" do
    stub_conn(session_id: "guest:abc", authenticated: false)

    subscribe uuid: conversation.uuid

    expect(subscription).to be_rejected
  end

  it "rejects unknown conversation uuids" do
    stub_conn(session_id: "sid-123", authenticated: true)

    subscribe uuid: "no-such-conversation"

    expect(subscription).to be_rejected
  end
end
