# frozen_string_literal: true

require "rails_helper"

# Pito::Stack instrumentation at the YouTube chokepoint
# (Channel::Youtube::Auditor#write_audit_row) — records even though the legacy
# YoutubeApiCall table is gone (the track call runs before that guard).
RSpec.describe Channel::Youtube::Auditor, type: :service do
  let(:auditor) do
    Class.new { include Channel::Youtube::Auditor }.new
  end

  it "records a youtube ApiRequest per audited call" do
    expect do
      auditor.send(:write_audit_row,
                   endpoint: "videos.list", http_method: "GET",
                   outcome: "ok", kind: "data", connection: nil)
    end.to change { ApiRequest.youtube.count }.by(1)
  end
end
