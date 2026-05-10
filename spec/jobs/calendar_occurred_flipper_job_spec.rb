require "rails_helper"

RSpec.describe CalendarOccurredFlipperJob, type: :job do
  it "invokes Calendar::OccurredFlipper#flip_ripe!" do
    expect(Calendar::OccurredFlipper).to receive(:flip_ripe!)
    described_class.new.perform
  end

  it "is registered as a Sidekiq cron at minute 5 of every hour" do
    schedule = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
    entry = schedule["calendar_occurred_flipper"]
    expect(entry).to be_present
    expect(entry["cron"]).to eq("5 * * * *")
    expect(entry["class"]).to eq("CalendarOccurredFlipperJob")
  end
end
