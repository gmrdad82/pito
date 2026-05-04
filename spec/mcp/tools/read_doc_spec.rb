require "rails_helper"
require_relative "../../../app/mcp/tools/read_doc"

RSpec.describe Mcp::Tools::ReadDoc do
  let(:tmproot) { Pathname.new(Dir.mktmpdir("pito-docs-read-spec")) }

  before do
    @real_root = Rails.root
    Rails.application.config.root = tmproot
    allow(Rails).to receive(:root).and_return(tmproot)

    FileUtils.mkdir_p(tmproot.join("docs"))
  end

  after do
    Rails.application.config.root = @real_root
    allow(Rails).to receive(:root).and_call_original
    FileUtils.remove_entry(tmproot) if tmproot.exist?
  end

  def write(rel, content)
    path = tmproot.join(rel)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, content)
    path
  end

  it "reads a docs/ markdown file" do
    write("docs/design.md", "# Design\nhello world\n")

    result = described_class.call(path: "docs/design.md")
    data = JSON.parse(result.content.first[:text])

    expect(data["path"]).to eq("docs/design.md")
    expect(data["content"]).to eq("# Design\nhello world\n")
    expect(data["last_modified_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
  end

  it "reads CLAUDE.md at repo root" do
    write("CLAUDE.md", "# Pito\nbody\n")

    result = described_class.call(path: "CLAUDE.md")
    data = JSON.parse(result.content.first[:text])

    expect(data["path"]).to eq("CLAUDE.md")
    expect(data["content"]).to eq("# Pito\nbody\n")
  end

  it "returns a clear error when the validated file is missing" do
    result = described_class.call(path: "docs/missing.md")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/not found/)
  end

  it "rejects a path containing ../ that escapes" do
    result = described_class.call(path: "../../etc/passwd")
    expect(result.to_h[:isError]).to be true
  end

  it "rejects an absolute path" do
    result = described_class.call(path: "/etc/passwd")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/relative/)
  end

  it "rejects Gemfile (root file but not CLAUDE.md, wrong extension)" do
    write("Gemfile", "source 'rubygems'\n")

    result = described_class.call(path: "Gemfile")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/\.md/)
  end

  it "rejects app/models/user.rb (wrong extension)" do
    result = described_class.call(path: "app/models/user.rb")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/\.md/)
  end

  it "rejects notes.txt (wrong extension)" do
    result = described_class.call(path: "docs/notes.txt")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/\.md/)
  end

  it "rejects an extensionless path" do
    result = described_class.call(path: "docs/notes")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/\.md/)
  end
end
