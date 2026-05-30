# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "pito:tools:games rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("pito:tools:games:backfill_scores")
  end

  before do
    Rake::Task["pito:tools:games:backfill_scores"].reenable
  end

  def suppress_output
    $stdout = File.open(File::NULL, "w")
    yield
  ensure
    $stdout = STDOUT
  end

  describe "pito:tools:games:backfill_scores" do
    it "backfills score from rating data even when auto-recompute already set it" do
      game = create(:game,
                    igdb_rating: 85.0, igdb_rating_count: 100)
      expect(game.score).to eq(85)

      game.update_column(:score, nil)
      expect { suppress_output { Rake::Task["pito:tools:games:backfill_scores"].invoke } }
        .to change { game.reload.score }.from(nil).to(85)
    end

    it "sets score to 0 for games with no rating data" do
      game = create(:game)
      expect(game.score).to be_nil

      expect { suppress_output { Rake::Task["pito:tools:games:backfill_scores"].invoke } }
        .to change { game.reload.score }.from(nil).to(0)
    end
  end
end
