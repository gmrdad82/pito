require "rails_helper"
require "ostruct"

# Phase 13.2 — Analytics sync engine. Defense-in-depth assertions on
# `Youtube::AnalyticsClient` — the connection bound at construction
# is the only authority for the request's identity.
RSpec.describe Youtube::AnalyticsClient, "flaw / smuggle assertions" do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user, access_token: "ya29.constructor-token") }
  let(:other_connection) { create(:youtube_connection, user: user, access_token: "ya29.foreign-token", google_subject_id: "subject-other-99") }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:foreign_channel) { create(:channel, youtube_connection: other_connection) }
  let(:from)       { Date.current - 3 }
  let(:to)         { Date.current - 1 }
  let(:svc) { instance_double(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService) }
  let(:client_options) do
    Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new
  end

  before do
    # Phase 13 security fix-forward (F1) — service construction now flows
    # through `Youtube::ServiceFactory.analytics_service`, which sets
    # bounded HTTP timeouts via `svc.client_options.*=` before assigning
    # the OAuth authorization adapter. The double therefore needs to
    # accept `client_options` and `authorization=` so the factory can
    # finish its work and hand back the same `svc` instance the spec
    # asserts against.
    allow(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService).to receive(:new).and_return(svc)
    allow(svc).to receive(:client_options).and_return(client_options)
    allow(svc).to receive(:authorization=)
    allow(svc).to receive(:query_report).and_return(
      OpenStruct.new(
        column_headers: [ OpenStruct.new(name: "day"), OpenStruct.new(name: "views") ],
        rows: [ [ "2026-05-09", 1 ] ]
      )
    )
  end

  it "ignores extra (smuggled) keyword arguments and uses only constructor-bound state" do
    # The signature is strict — extra kwargs raise ArgumentError. That
    # itself is the flaw guard: a caller cannot smuggle a foreign
    # connection_id through a kwarg.
    expect {
      described_class.new(connection: connection).channel_daily(
        channel: channel, from: from, to: to, connection_id: other_connection.id
      )
    }.to raise_error(ArgumentError)
  end

  it "uses only the constructor's connection.access_token, never a cached one" do
    described_class.new(connection: connection).channel_daily(
      channel: channel, from: from, to: to
    )

    # Capture the authorization adapter the service was given and
    # confirm it Apply!s the constructor connection's token.
    captured = nil
    allow(svc).to receive(:authorization=) { |adapter| captured = adapter }

    described_class.new(connection: connection).channel_daily(
      channel: channel, from: from, to: to
    )
    headers = {}
    captured.apply!(headers)
    expect(headers["Authorization"]).to eq("Bearer #{connection.access_token}")
  end

  it "rejects a channel that does not belong to the constructor's connection" do
    expect {
      described_class.new(connection: connection).channel_daily(
        channel: foreign_channel, from: from, to: to
      )
    }.to raise_error(ArgumentError, /does not belong to connection/)
  end

  it "writes audit rows under the constructor's connection_id (source-of-truth)" do
    described_class.new(connection: connection).channel_daily(
      channel: channel, from: from, to: to
    )
    row = YoutubeApiCall.unscoped.last
    expect(row.youtube_connection_id).to eq(connection.id)
    expect(row.youtube_connection_id).not_to eq(other_connection.id)
  end
end
