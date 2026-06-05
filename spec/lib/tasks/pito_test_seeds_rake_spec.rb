# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "pathname"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:test:seeds:prepare", type: :rake do
  before(:all) { load_tasks }

  let(:seeds_dir) { Pathname.new(Dir.mktmpdir("pito_seeds")) }

  before do
    stub_const("SEEDS_DIR", seeds_dir)
    stub_const("FILES_DIR", seeds_dir.join("files"))
    reenable("pito:test:seeds:prepare")
  end

  after { FileUtils.rm_rf(seeds_dir) }

  it "writes YAML files for every table" do
    suppress_output { Rake::Task["pito:test:seeds:prepare"].invoke }

    expect(seeds_dir.join("manifest.yml")).to exist
    expect(seeds_dir.join("channels.yml")).to exist
    expect(seeds_dir.join("games.yml")).to exist
  end

  it "records row counts in the manifest" do
    create_list(:channel, 2)
    create(:game)

    suppress_output { Rake::Task["pito:test:seeds:prepare"].invoke }

    manifest = YAML.load_file(seeds_dir.join("manifest.yml"))
    expect(manifest[:tables]["channels"]).to eq(2)
    expect(manifest[:tables]["games"]).to be >= 1
  end
end
