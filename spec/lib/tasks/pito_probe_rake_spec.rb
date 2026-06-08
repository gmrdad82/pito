# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"
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

  it "aborts when no mp4/mkv/mov files match the glob" do
    game = create(:game)
    ENV["game"] = game.id.to_s
    # JSON fixtures are not video extensions → the task filters them all out.
    ENV["path"] = Rails.root.join("spec/fixtures/files/ffprobe/*.json").to_s

    suppress_output do
      expect { Rake::Task["pito:tools:probe"].invoke }.to raise_error(SystemExit)
    end
  end

  it "probes matching video files without crashing (skips unprobeable ones)" do
    game = create(:game)

    Dir.mktmpdir do |dir|
      # A .mp4 passes the extension filter so the task proceeds; ffprobe fails
      # on the fake content, so the file is skipped (no Footage) but the task
      # completes WITHOUT aborting.
      File.write(File.join(dir, "clip.mp4"), "not a real video")

      ENV["game"] = game.id.to_s
      ENV["path"] = File.join(dir, "*.mp4")

      suppress_output { Rake::Task["pito:tools:probe"].invoke }

      expect(Footage.where(game: game)).to be_empty
    end
  end
end
