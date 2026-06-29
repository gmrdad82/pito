# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompactJob, type: :job do
  it "is a no-op that does not raise" do
    expect { described_class.new.perform(42) }.not_to raise_error
  end

  it "logs the compact request" do
    allow(Rails.logger).to receive(:info)
    described_class.new.perform(99)
    expect(Rails.logger).to have_received(:info).with(/compact requested for conversation 99/)
  end
end
