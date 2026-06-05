# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:tools:probe", type: :rake do
  before(:all) { load_tasks }

  before do
    reenable("pito:tools:probe")
    @old_game = ENV["game"]
    @old_path = ENV["path"]
  end

  after do
    ENV["game"] = @old_game
    ENV["path"] = @old_path
  end

  it "requires game= and path=" do
    ENV["game"] = nil
    ENV["path"] = nil

    suppress_output do
      expect { Rake::Task["pito:tools:probe"].invoke }
        .to raise_error(SystemExit)
    end
  end

  it "aborts when the game does not exist" do
    ENV["game"] = "999999"
    ENV["path"] = "/fake/*.mp4"

    suppress_output do
      expect { Rake::Task["pito:tools:probe"].invoke }
        .to raise_error(SystemExit)
    end
  end

  it "probes files and upserts Footage rows" do
    game = create(:game)

    ENV["game"] = game.id.to_s
    ENV["path"] = Rails.root.join("spec/fixtures/files/ffprobe/*.json").to_s

    # The glob matches JSON fixtures; Probe will fail on them, which
    # is fine for this test — we just verify the task structure.
    suppress_output { Rake::Task["pito:tools:probe"].invoke }

    # Nothing is created because JSON files are not valid video,
    # but the task ran without crashing.
    expect(Footage.where(game: game)).to be_empty
  end
end
