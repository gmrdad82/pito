require "rails_helper"

RSpec.describe DevDocPath do
  describe ".resolve" do
    it "accepts a docs/ markdown file" do
      result = described_class.resolve("docs/design.md")
      expect(result).to eq(Rails.root.join("docs/design.md"))
    end

    it "accepts a deeply nested docs path" do
      result = described_class.resolve("docs/plans/beta/03-channel-revamp/log.md")
      expect(result).to eq(Rails.root.join("docs/plans/beta/03-channel-revamp/log.md"))
    end

    it "accepts CLAUDE.md at repo root" do
      result = described_class.resolve("CLAUDE.md")
      expect(result).to eq(Rails.root.join("CLAUDE.md"))
    end

    it "accepts cleanpath equivalents like docs/./design.md" do
      result = described_class.resolve("docs/./design.md")
      expect(result).to eq(Rails.root.join("docs/design.md"))
    end

    it "rejects nil with a clear error" do
      expect { described_class.resolve(nil) }.to raise_error(DevDocPath::Error, /required/)
    end

    it "rejects empty string" do
      expect { described_class.resolve("") }.to raise_error(DevDocPath::Error, /required/)
    end

    it "rejects whitespace-only input" do
      expect { described_class.resolve("   ") }.to raise_error(DevDocPath::Error, /required/)
    end

    it "rejects paths starting with /" do
      expect { described_class.resolve("/etc/passwd") }
        .to raise_error(DevDocPath::Error, /must be relative/)
    end

    it "rejects paths containing .. that escape" do
      expect { described_class.resolve("../../etc/passwd") }
        .to raise_error(DevDocPath::Error, /(\.\.|inside docs)/)
    end

    it "rejects paths whose cleanpath would still leave .." do
      # `docs/../../foo.md` cleans to `../foo.md`. The helper rejects it.
      expect { described_class.resolve("docs/../../foo.md") }
        .to raise_error(DevDocPath::Error, /\.\./)
    end

    it "rejects non-.md extensions" do
      expect { described_class.resolve("docs/notes.txt") }
        .to raise_error(DevDocPath::Error, /\.md/)
    end

    it "rejects extensionless paths" do
      expect { described_class.resolve("docs/notes") }
        .to raise_error(DevDocPath::Error, /\.md/)
    end

    it "rejects Gemfile (root file but not CLAUDE.md)" do
      expect { described_class.resolve("Gemfile") }
        .to raise_error(DevDocPath::Error, /\.md/)
    end

    it "rejects app/models/user.rb (wrong tree, wrong extension)" do
      expect { described_class.resolve("app/models/user.rb") }
        .to raise_error(DevDocPath::Error, /\.md/)
    end

    it "rejects an .md file outside docs/ that isn't CLAUDE.md" do
      # README.md at the root would not satisfy either branch.
      expect { described_class.resolve("README.md") }
        .to raise_error(DevDocPath::Error, /inside docs/)
    end
  end

  describe ".inside?" do
    let(:root) { Rails.root.join("docs").cleanpath }

    it "is true for the root itself" do
      expect(described_class.inside?(root, root)).to be true
    end

    it "is true for a descendant" do
      expect(described_class.inside?(root.join("design.md"), root)).to be true
    end

    it "is true for a deep descendant" do
      expect(described_class.inside?(root.join("plans/beta/03-channel-revamp/log.md"), root)).to be true
    end

    it "is false for a sibling sharing a prefix" do
      # `docsy/file.md` must not be considered inside `docs/`.
      sibling = Rails.root.join("docsy/file.md").cleanpath
      expect(described_class.inside?(sibling, root)).to be false
    end

    it "is false for an unrelated path" do
      expect(described_class.inside?(Rails.root.join("Gemfile").cleanpath, root)).to be false
    end
  end
end
