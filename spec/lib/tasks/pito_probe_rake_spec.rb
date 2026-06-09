# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:tools:probe", type: :rake do
  before(:all) { load_tasks }

  before do
    reenable("pito:tools:probe")
    @old_game  = ENV["game"]
    @old_path  = ENV["path"]
    @old_force = ENV["force"]
  end

  after do
    ENV["game"]  = @old_game
    ENV["path"]  = @old_path
    ENV["force"] = @old_force
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

  describe "incremental (only new files)" do
    it "skips a file already imported for the game — does NOT re-probe it" do
      game = create(:game)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "clip.mp4"), "x")
        Footage.create!(game: game, filename: "clip.mp4") # already imported

        ENV["game"] = game.id.to_s
        ENV["path"] = File.join(dir, "*.mp4")

        # Incremental skip means the prober is never invoked for this file.
        expect(Pito::Footage::Probe).not_to receive(:call)
        suppress_output { Rake::Task["pito:tools:probe"].invoke }

        expect(Footage.where(game: game).count).to eq(1)
      end
    end

    it "force=1 re-probes an already-imported file" do
      game = create(:game)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "clip.mp4"), "x")
        Footage.create!(game: game, filename: "clip.mp4")

        ENV["game"]  = game.id.to_s
        ENV["path"]  = File.join(dir, "*.mp4")
        ENV["force"] = "1"

        # With force, the prober IS called even though the row exists. Stub the
        # result (no real ffprobe) so the assertion is deterministic.
        probe_failure = double(success: false, error_message: "stub")
        expect(Pito::Footage::Probe).to receive(:call).and_return(probe_failure)
        suppress_output { Rake::Task["pito:tools:probe"].invoke }
      end
    end
  end
end
