require "rails_helper"
require_relative "../../../app/mcp/tools/list_docs"

RSpec.describe Mcp::Tools::ListDocs do
  # Sandbox docs/ tree under a tmpdir and rebind Rails.root for these
  # specs only. This keeps the suite hermetic — we don't read or list
  # real project docs, and we don't write into the live tree.
  let(:tmproot) { Pathname.new(Dir.mktmpdir("pito-docs-spec")) }

  before do
    @real_root = Rails.root
    Rails.application.config.root = tmproot
    allow(Rails).to receive(:root).and_return(tmproot)

    FileUtils.mkdir_p(tmproot.join("docs/plans/beta/01-foo"))
    FileUtils.mkdir_p(tmproot.join("docs/decisions"))
  end

  after do
    Rails.application.config.root = @real_root
    allow(Rails).to receive(:root).and_call_original
    FileUtils.remove_entry(tmproot) if tmproot.exist?
  end

  def write(rel, content, mtime: nil)
    path = tmproot.join(rel)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, content)
    File.utime(mtime.to_time, mtime.to_time, path) if mtime
    path
  end

  it "lists .md files relative to repo root" do
    write("docs/design.md", "# Design\n")
    write("docs/plans/beta/01-foo/log.md", "# Log\n")

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    paths = data.map { |r| r["path"] }
    expect(paths).to include("docs/design.md", "docs/plans/beta/01-foo/log.md")
  end

  it "returns the documented row shape" do
    write("docs/design.md", "# Design\nhello\n")

    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    row = data.find { |r| r["path"] == "docs/design.md" }

    expect(row.keys).to contain_exactly("path", "last_modified_at", "size_bytes", "first_heading")
    expect(row["first_heading"]).to eq("Design")
    expect(row["size_bytes"]).to be > 0
    expect(row["last_modified_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
  end

  it "returns empty first_heading when the file has no H1" do
    write("docs/no-heading.md", "no heading here\njust prose\n")

    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    row = data.find { |r| r["path"] == "docs/no-heading.md" }

    expect(row["first_heading"]).to eq("")
  end

  it "ignores ## level-2 headings when looking for the first H1" do
    write("docs/h2-only.md", "## Subheading\nbody\n")

    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    row = data.find { |r| r["path"] == "docs/h2-only.md" }

    expect(row["first_heading"]).to eq("")
  end

  it "filters by name_pattern" do
    write("docs/plans/beta/01-foo/log.md", "# Log\n")
    write("docs/plans/beta/01-foo/plan.md", "# Plan\n")
    write("docs/design.md", "# Design\n")

    result = described_class.call(name_pattern: "log.md")
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["path"] }).to contain_exactly("docs/plans/beta/01-foo/log.md")
  end

  it "filters by prefix (relative to docs/)" do
    write("docs/design.md", "# Design\n")
    write("docs/decisions/0001-foo.md", "# Foo\n")
    write("docs/decisions/0002-bar.md", "# Bar\n")

    result = described_class.call(prefix: "decisions/")
    data = JSON.parse(result.content.first[:text])

    paths = data.map { |r| r["path"] }
    expect(paths).to contain_exactly("docs/decisions/0001-foo.md", "docs/decisions/0002-bar.md")
  end

  it "includes CLAUDE.md when prefix is empty and the pattern matches" do
    write("CLAUDE.md", "# Pito\n")
    write("docs/design.md", "# Design\n")

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["path"] }).to include("CLAUDE.md", "docs/design.md")
  end

  it "excludes CLAUDE.md when a prefix is set" do
    write("CLAUDE.md", "# Pito\n")
    write("docs/design.md", "# Design\n")

    result = described_class.call(prefix: "decisions/")
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["path"] }).not_to include("CLAUDE.md")
  end

  it "excludes CLAUDE.md when name_pattern doesn't match it" do
    write("CLAUDE.md", "# Pito\n")
    write("docs/plans/beta/01-foo/log.md", "# Log\n")

    result = described_class.call(name_pattern: "log.md")
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["path"] }).to contain_exactly("docs/plans/beta/01-foo/log.md")
  end

  it "sorts by mtime_desc by default" do
    older = write("docs/old.md", "# Old\n", mtime: 1.day.ago)
    newer = write("docs/new.md", "# New\n", mtime: Time.current)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    paths = data.map { |r| r["path"] }

    expect(paths.index("docs/new.md")).to be < paths.index("docs/old.md")
  end

  it "sorts by mtime_asc" do
    write("docs/old.md", "# Old\n", mtime: 1.day.ago)
    write("docs/new.md", "# New\n", mtime: Time.current)

    result = described_class.call(sort: "mtime_asc")
    data = JSON.parse(result.content.first[:text])
    paths = data.map { |r| r["path"] }

    expect(paths.index("docs/old.md")).to be < paths.index("docs/new.md")
  end

  it "sorts by path" do
    write("docs/zebra.md", "# Z\n")
    write("docs/alpha.md", "# A\n")
    write("docs/middle.md", "# M\n")

    result = described_class.call(sort: "path")
    data = JSON.parse(result.content.first[:text])
    paths = data.map { |r| r["path"] }

    expect(paths).to eq(paths.sort)
  end

  it "honors limit" do
    5.times { |i| write("docs/file-#{i}.md", "# #{i}\n") }

    result = described_class.call(limit: 2)
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(2)
  end

  it "clamps limit to the 1..500 range" do
    write("docs/x.md", "# X\n")

    result = described_class.call(limit: 0)
    expect(JSON.parse(result.content.first[:text]).size).to eq(1)

    result = described_class.call(limit: -50)
    expect(JSON.parse(result.content.first[:text]).size).to eq(1)
  end

  it "rejects an unknown sort value" do
    result = described_class.call(sort: "alphabetical")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/sort/)
  end

  it "rejects an absolute prefix" do
    result = described_class.call(prefix: "/etc")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/relative/)
  end

  it "rejects a prefix containing ..  segments" do
    result = described_class.call(prefix: "../etc")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/\.\./)
  end
end
