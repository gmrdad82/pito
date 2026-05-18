require "rails_helper"

RSpec.describe StackStatsChannel, type: :channel do
  it "subscribes successfully and streams from the `stack_stats` broadcasting" do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("stack_stats")
  end
end
