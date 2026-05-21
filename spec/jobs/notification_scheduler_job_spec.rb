require "rails_helper"

RSpec.describe NotificationSchedulerJob do
  describe "#perform" do
    it "delegates to Pito::Notifications::Scheduler" do
      scheduler = instance_double(Pito::Notifications::Scheduler)
      expect(Pito::Notifications::Scheduler).to receive(:new).and_return(scheduler)
      expect(scheduler).to receive(:perform)
      described_class.new.perform
    end
  end

  describe "cron registration" do
    it "is registered in config/sidekiq_cron.yml every minute" do
      schedule_path = Rails.root.join("config", "sidekiq_cron.yml")
      cron = YAML.load_file(schedule_path)
      entry = cron["notification_scheduler"]
      expect(entry).to be_present
      expect(entry["class"]).to eq("NotificationSchedulerJob")
      expect(entry["cron"]).to eq("* * * * *")
    end
  end
end
