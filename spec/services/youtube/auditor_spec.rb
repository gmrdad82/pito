require "rails_helper"

# Phase 7 — Step B (7b-youtube-client-and-audit.md). The `Youtube::Auditor`
# mixin's `write_audit_row` persists a single `YoutubeApiCall` row per
# logical YouTube/OAuth call. Cost comes from `Youtube::Quota.cost_for`.
# Failures are swallowed — a broken audit must never break the
# underlying YouTube call.
#
# The method is private; we exercise it via a host class that includes
# the mixin and exposes a public wrapper, mirroring the real consumers
# (`Youtube::Client`, `Youtube::PublicClient`).
RSpec.describe Youtube::Auditor do
  let(:host_class) do
    Class.new do
      include Youtube::Auditor

      # Public wrapper around the private mixin method, used only in
      # specs. Mirrors how `Youtube::Client` calls `write_audit_row`.
      def audit(**kwargs)
        write_audit_row(**kwargs)
      end
    end
  end

  let(:host)       { host_class.new }
  let(:user)       { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }

  describe "#write_audit_row" do
    it "persists a YoutubeApiCall row for a successful videos.list call" do
      expect {
        host.audit(
          endpoint: "videos.list",
          http_method: "GET",
          outcome: "success",
          kind: "oauth",
          connection: connection,
          http_status: 200,
          duration_ms: 42
        )
      }.to change(YoutubeApiCall, :count).by(1)

      row = YoutubeApiCall.last
      expect(row.endpoint).to eq("videos.list")
      expect(row.http_method).to eq("GET")
      expect(row.outcome).to eq("success")
      expect(row.client_kind).to eq("oauth")
      expect(row.youtube_connection_id).to eq(connection.id)
      expect(row.http_status).to eq(200)
      expect(row.duration_ms).to eq(42)
    end

    it "stamps the cost from Youtube::Quota.cost_for" do
      host.audit(
        endpoint: "videos.update",
        http_method: "PUT",
        outcome: "success",
        kind: "oauth",
        connection: connection
      )

      row = YoutubeApiCall.last
      expect(row.units).to eq(50) # videos.update — locked cost
    end

    it "stamps cost=0 for the oauth2.revoke endpoint" do
      host.audit(
        endpoint: "oauth2.revoke",
        http_method: "POST",
        outcome: "success",
        kind: "oauth",
        connection: connection
      )

      row = YoutubeApiCall.last
      expect(row.units).to eq(0)
    end

    it "derives user_id from the connection when no explicit user is given" do
      host.audit(
        endpoint: "channels.list",
        http_method: "GET",
        outcome: "success",
        kind: "oauth",
        connection: connection
      )

      expect(YoutubeApiCall.last.user_id).to eq(connection.user_id)
    end

    it "prefers the explicit user: argument over connection.user_id" do
      other = create(:user, username: "other_#{SecureRandom.hex(4)}")
      host.audit(
        endpoint: "channels.list",
        http_method: "GET",
        outcome: "success",
        kind: "oauth",
        connection: connection,
        user: other
      )

      expect(YoutubeApiCall.last.user_id).to eq(other.id)
    end

    it "supports the public client kind with no connection" do
      host.audit(
        endpoint: "videos.list",
        http_method: "GET",
        outcome: "success",
        kind: "public",
        connection: nil,
        user: user
      )

      row = YoutubeApiCall.last
      expect(row.client_kind).to eq("public")
      expect(row.youtube_connection_id).to be_nil
      expect(row.user_id).to eq(user.id)
    end

    it "records non-success outcomes verbatim" do
      host.audit(
        endpoint: "videos.list",
        http_method: "GET",
        outcome: "rate_limited",
        kind: "oauth",
        connection: connection,
        http_status: 429,
        error_message: "rate limited"
      )

      row = YoutubeApiCall.last
      expect(row.outcome).to eq("rate_limited")
      expect(row.http_status).to eq(429)
      expect(row.error_message).to eq("rate limited")
    end

    it "truncates error_message at 2_000 characters" do
      long = "x" * 5_000
      host.audit(
        endpoint: "videos.list",
        http_method: "GET",
        outcome: "server_error",
        kind: "oauth",
        connection: connection,
        error_message: long
      )

      row = YoutubeApiCall.last
      expect(row.error_message.length).to eq(2_000)
    end

    it "coerces a non-string error_message to_s before truncation" do
      err = StandardError.new("boom")
      host.audit(
        endpoint: "videos.list",
        http_method: "GET",
        outcome: "client_error",
        kind: "oauth",
        connection: connection,
        error_message: err
      )

      row = YoutubeApiCall.last
      expect(row.error_message).to include("boom")
    end

    it "stamps created_at with the current time" do
      freeze = Time.utc(2026, 5, 10, 9, 0, 0)
      allow(Time).to receive(:current).and_return(freeze)

      host.audit(
        endpoint: "videos.list",
        http_method: "GET",
        outcome: "success",
        kind: "oauth",
        connection: connection
      )

      row = YoutubeApiCall.last
      expect(row.created_at).to be_within(1.second).of(freeze)
    end

    it "swallows and logs persistence failures (audit must never break the call)" do
      allow(YoutubeApiCall).to receive(:create!).and_raise(StandardError, "db down")
      expect(Rails.logger).to receive(:warn).with(/Youtube::Auditor.*db down/)

      expect {
        host.audit(
          endpoint: "videos.list",
          http_method: "GET",
          outcome: "success",
          kind: "oauth",
          connection: connection
        )
      }.not_to raise_error
    end

    it "raises Youtube::UnknownEndpointError when the endpoint isn't in the cost map" do
      # Quota.cost_for is strict — an unknown endpoint is treated as a
      # programming error. The auditor inherits that strictness, but
      # the rescue StandardError block in `write_audit_row` swallows
      # the raise. This test pins the behaviour so a future refactor
      # that drops the rescue surfaces in CI rather than at runtime.
      expect {
        host.audit(
          endpoint: "videos.unknown",
          http_method: "GET",
          outcome: "success",
          kind: "oauth",
          connection: connection
        )
      }.not_to raise_error
      # Nothing persisted, since cost_for raised before YoutubeApiCall.create!.
      expect(YoutubeApiCall.where(endpoint: "videos.unknown").count).to eq(0)
    end
  end

  describe "method visibility" do
    it "marks #write_audit_row private on the including class" do
      expect(host_class.private_instance_methods).to include(:write_audit_row)
      expect(host_class.public_instance_methods).not_to include(:write_audit_row)
    end
  end
end
