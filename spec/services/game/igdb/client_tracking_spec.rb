# frozen_string_literal: true

require "rails_helper"

# Pito::Stack instrumentation at the IGDB chokepoint (Client#post).
# The track call fires inside the rate-limiter block BEFORE the HTTP request,
# so we stub the request itself away (the real request path is repaired in P7).
RSpec.describe Game::Igdb::Client, type: :service do
  it "records an igdb ApiRequest at the request chokepoint" do
    allow_any_instance_of(described_class).to receive(:perform_request).and_raise(StandardError, "stop")

    expect do
      described_class.new.search_games("zelda")
    rescue StandardError
      nil
    end.to change { ApiRequest.igdb.count }.by(1)
  end
end
