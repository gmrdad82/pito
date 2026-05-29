require "rails_helper"
require "rake"

RSpec.describe "pito:tools:assets rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("pito:tools:assets:setup_symlinks")
  end

  around do |example|
    Dir.mktmpdir("pito-assets-spec") do |tmpdir|
      old = ENV["PITO_ASSETS_PATH"]
      ENV["PITO_ASSETS_PATH"] = tmpdir
      example.run
    ensure
      ENV["PITO_ASSETS_PATH"] = old
    end
  end

  before do
    Rake::Task["pito:tools:assets:setup_symlinks"].reenable
  end

  describe "pito:tools:assets:setup_symlinks" do
    let(:covers_link)     { Rails.root.join("public", "covers") }
    let(:thumbnails_link) { Rails.root.join("public", "thumbnails") }

    after do
      File.unlink(covers_link)     if File.symlink?(covers_link)
      File.unlink(thumbnails_link) if File.symlink?(thumbnails_link)
    end

    it "creates symlinks for covers and thumbnails" do
      Rake::Task["pito:tools:assets:setup_symlinks"].invoke
      expect(File.symlink?(covers_link)).to be true
      expect(File.symlink?(thumbnails_link)).to be true
    end

    it "is idempotent — re-running does not raise" do
      Rake::Task["pito:tools:assets:setup_symlinks"].invoke
      Rake::Task["pito:tools:assets:setup_symlinks"].reenable
      expect { Rake::Task["pito:tools:assets:setup_symlinks"].invoke }.not_to raise_error
    end

    it "prints a completion message" do
      expect { Rake::Task["pito:tools:assets:setup_symlinks"].invoke }
        .to output(/setup_symlinks.*done/i).to_stdout
    end
  end
end
