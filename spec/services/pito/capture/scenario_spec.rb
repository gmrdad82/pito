# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Capture::Scenario do
  def build(overrides = {})
    described_class.new({
      "name"     => "demo",
      "base_url" => "http://localhost:3027",
      "steps"    => [ { "shot" => "demo.png" } ]
    }.merge(overrides))
  end

  it "parses name, base_url, steps and merges the default viewport" do
    s = build("viewport" => { "width" => 800 })
    expect(s.name).to eq("demo")
    expect(s.viewport).to eq({ "width" => 800, "height" => 900, "scale" => 2 })
  end

  it "confines output under tmp/captures/<name> — shipped images can never be overwritten" do
    expect(build.output_dir(root: Pathname.new("/repo")).to_s).to eq("/repo/tmp/captures/demo")
  end

  it "rejects an unknown step loudly" do
    expect { build("steps" => [ { "teleport" => true } ]) }
      .to raise_error(described_class::InvalidScenario, /not a known step/)
  end

  it "rejects shot/gif names with path traversal or directories" do
    expect { build("steps" => [ { "shot" => "../../docs/media/x.png" } ]) }
      .to raise_error(described_class::InvalidScenario, /bare .png/)
    expect { build("steps" => [ { "gif" => { "name" => "sub/dir.gif" } } ]) }
      .to raise_error(described_class::InvalidScenario, /bare .png/)
  end

  it "rejects a filesystem-unsafe scenario name" do
    expect { build("name" => "../evil") }
      .to raise_error(described_class::InvalidScenario, /filesystem-safe/)
  end

  it "requires base_url and at least one step" do
    expect { build("base_url" => "") }.to raise_error(described_class::InvalidScenario, /base_url/)
    expect { build("steps" => []) }.to raise_error(described_class::InvalidScenario, /non-empty/)
  end

  it "loads every committed pito scenario cleanly (config/captures integrity)" do
    expect(described_class.all.map(&:name)).to include("ls-channels", "ls-vids")
  end

  it "loads the pitomd set from lib/support/pitomd with scoped, non-colliding output" do
    scenarios = described_class.pitomd
    expect(scenarios.map(&:name)).to include("mkt-landing")
    expect(scenarios.first.output_dir(root: Pathname.new("/repo")).to_s)
      .to start_with("/repo/tmp/captures/pitomd/")
  end
end
