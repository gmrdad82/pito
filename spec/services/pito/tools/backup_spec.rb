# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Pito::Tools::Backup, type: :service do
  let(:root)    { Pathname(Dir.mktmpdir) }
  let(:storage) { Pathname(Dir.mktmpdir).tap { |d| (d / "blob.bin").write("x") } }
  let(:io)      { StringIO.new }
  let(:clock)   { Time.zone.local(2026, 6, 18, 9, 5, 3) }

  subject(:backup) { described_class.new(root:, out: io, clock:) }

  before do
    # Never invoke the real pg_dump/tar in specs — simulate the shell-out by
    # creating the artifact file it would have produced.
    allow(backup).to receive(:run!) { |_label, _cmd, path, **| FileUtils.touch(path); path }
    allow(backup).to receive(:storage_root).and_return(storage)
  end

  after do
    FileUtils.rm_rf(root)
    FileUtils.rm_rf(storage)
  end

  let(:expected_dir) { root.join("backup", "2026-06-18 09-05-03") }

  it "creates a timestamped backup/<yyyy-mm-dd hh-mm-ss> folder" do
    result = backup.call
    expect(result.dir).to eq(expected_dir)
    expect(expected_dir).to be_directory
  end

  it "produces the gzipped database dump and asset archive" do
    backup.call
    expect(expected_dir.join("database.sql.gz")).to exist
    expect(expected_dir.join("active_storage.tar.gz")).to exist
  end

  it "returns both artifacts" do
    expect(backup.call.artifacts.map { |p| p.basename.to_s })
      .to contain_exactly("database.sql.gz", "active_storage.tar.gz")
  end

  it "prints step-by-step progress" do
    backup.call
    expect(io.string).to include("Backing up to", "pg_dump", "tar", "Done —", "database.sql.gz")
  end

  it "shells out to pg_dump (→ gzip) and tar (→ gzip) via system tools" do
    commands = []
    allow(backup).to receive(:run!) { |_l, cmd, path, **| commands << cmd; FileUtils.touch(path); path }
    backup.call
    expect(commands).to include(a_string_matching(%r{pg_dump.*\| gzip -c >}))
    expect(commands).to include(a_string_matching(%r{tar -czf .* -C .* \.}))
  end

  context "when ActiveStorage has no Disk root (e.g. S3)" do
    before { allow(backup).to receive(:storage_root).and_return(nil) }

    it "skips the asset archive but still dumps the database" do
      result = backup.call
      expect(result.artifacts.map { |p| p.basename.to_s }).to eq([ "database.sql.gz" ])
      expect(io.string).to include("skipped")
    end
  end
end
