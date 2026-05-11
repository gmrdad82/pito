require "rails_helper"
require "rake"

# Spec for `lib/tasks/pito.rake`. The tasks here are one-off operator
# helpers; each spec loads the task file in isolation, reinvokes the
# named task, and asserts on database side effects + the line of stdout
# the task prints.
RSpec.describe "pito rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:drop_seeded_channels"] }

  before do
    task.reenable
  end

  def valid_url(i)
    suffix = ("a".."z").to_a[i].to_s * 22
    "https://www.youtube.com/channel/UC#{suffix[0, 22]}"
  end

  describe "pito:drop_seeded_channels" do
    it "deletes channels with NULL youtube_connection_id" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      expect { task.invoke }.to change { Channel.count }.by(-2)
    end

    it "preserves channels that carry a youtube_connection_id" do
      connection = FactoryBot.create(:youtube_connection)
      kept = Channel.create!(channel_url: valid_url(0),
                             youtube_connection_id: connection.id)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      task.invoke
      expect(Channel.exists?(kept.id)).to be(true)
      expect(Channel.where(youtube_connection_id: nil)).to be_empty
    end

    it "is idempotent — re-running drops zero rows" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      task.invoke
      task.reenable
      expect { task.invoke }.not_to change { Channel.count }
    end

    it "prints a count line when rows are dropped" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      expect { task.invoke }.to output(/dropped 2 seeded channels\./).to_stdout
    end

    it "prints a singular count line when one row is dropped" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      expect { task.invoke }.to output(/dropped 1 seeded channel\./).to_stdout
    end

    it "prints a no-op message when nothing matches" do
      expect { task.invoke }.to output(/no seeded channels to drop\./).to_stdout
    end

    it "cascades through dependent Video rows so no orphans remain" do
      channel = Channel.create!(channel_url: valid_url(0),
                                youtube_connection_id: nil)
      video = Video.create!(channel: channel, youtube_video_id: "abcd1234567")
      task.invoke
      expect(Channel.exists?(channel.id)).to be(false)
      expect(Video.exists?(video.id)).to be(false)
    end
  end
end
