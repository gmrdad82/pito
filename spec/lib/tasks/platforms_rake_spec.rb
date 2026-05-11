require "rails_helper"
require "rake"

# Phase 27 §1a — `rake platforms:sync_from_igdb` is the manual lever
# that triggers the same IGDB upsert the weekly cron entry runs.
RSpec.describe "platforms rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/platforms",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["platforms:sync_from_igdb"] }

  before do
    task.reenable
  end

  describe "platforms:sync_from_igdb" do
    it "invokes Platforms::SyncFromIgdbJob#perform" do
      job = instance_double(Platforms::SyncFromIgdbJob,
                            perform: Platforms::SyncFromIgdb::Result.new(
                              created: 0, updated: 0, total: 0
                            ))
      allow(Platforms::SyncFromIgdbJob).to receive(:new).and_return(job)

      task.invoke

      expect(job).to have_received(:perform)
    end

    it "prints the created / updated / total counts" do
      job = instance_double(Platforms::SyncFromIgdbJob,
                            perform: Platforms::SyncFromIgdb::Result.new(
                              created: 1, updated: 2, total: 3
                            ))
      allow(Platforms::SyncFromIgdbJob).to receive(:new).and_return(job)

      expect { task.invoke }.to output(
        /created=1 updated=2 total=3/
      ).to_stdout
    end

    it "loads with no error" do
      expect(Rake::Task.task_defined?("platforms:sync_from_igdb")).to be(true)
    end
  end
end
