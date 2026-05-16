require "rails_helper"
require "rake"
require "fileutils"
require "tmpdir"
require "yaml"

# Phase 29 (settings refactor) — pito:config:* rake task surface.
#
# The tasks read + write `config/pito.yml`. We redirect the YAML path
# to a per-spec temp file via stub_const so the live config doesn't
# leak across tests (the suite must not mutate the operator's actual
# yaml).
RSpec.describe "pito:config:* rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_config",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:tmp_path) do
    Pathname.new(Dir.mktmpdir).join("pito.yml")
  end

  before do
    # Redirect both the task helpers and the loader at the temp file.
    stub_const("PITO_CONFIG_PATH", tmp_path)
    stub_const("Pito::Config::PATH", tmp_path)
  end

  after do
    File.delete(tmp_path) if File.exist?(tmp_path)
    FileUtils.rm_rf(tmp_path.dirname) if File.directory?(tmp_path.dirname)
  end

  def invoke(name, args = nil)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*Array(args))
  end

  describe "pito:config:show" do
    it "prints defaults when the file is missing" do
      output = capture_stdout { invoke("pito:config:show") }
      expect(output).to include("max_panes:         3")
      expect(output).to include("pane_title_length: 14")
      expect(output).to include("timezone:          UTC")
      expect(output).to include("source:            #{tmp_path}")
    end

    it "prints the current values when the file is present" do
      File.write(tmp_path, { "max_panes" => 7, "pane_title_length" => 30, "timezone" => "Europe/Bucharest" }.to_yaml)
      output = capture_stdout { invoke("pito:config:show") }
      expect(output).to include("max_panes:         7")
      expect(output).to include("pane_title_length: 30")
      expect(output).to include("timezone:          Europe/Bucharest")
    end
  end

  describe "pito:config:max_panes:get" do
    it "prints the default when the file is missing" do
      output = capture_stdout { invoke("pito:config:max_panes:get") }
      expect(output.strip).to eq("3")
    end

    it "prints the current value" do
      File.write(tmp_path, { "max_panes" => 8 }.to_yaml)
      output = capture_stdout { invoke("pito:config:max_panes:get") }
      expect(output.strip).to eq("8")
    end
  end

  describe "pito:config:max_panes:set" do
    it "writes a valid integer" do
      output = capture_stdout { invoke("pito:config:max_panes:set", 5) }
      expect(output).to include("max_panes set to 5.")
      expect(output).to include("(restart Puma")
      expect(YAML.safe_load_file(tmp_path)["max_panes"]).to eq(5)
    end

    it "preserves other keys on set" do
      File.write(tmp_path, { "max_panes" => 3, "timezone" => "Europe/Paris" }.to_yaml)
      invoke("pito:config:max_panes:set", 6)
      data = YAML.safe_load_file(tmp_path)
      expect(data["max_panes"]).to eq(6)
      expect(data["timezone"]).to eq("Europe/Paris")
    end

    it "rejects an out-of-range value" do
      output = capture_stdout { expect { invoke("pito:config:max_panes:set", 99) }.to raise_error(SystemExit) }
      expect(output).to include("out of range")
    end

    it "rejects a non-integer value" do
      output = capture_stdout { expect { invoke("pito:config:max_panes:set", "five") }.to raise_error(SystemExit) }
      expect(output).to include("not an integer")
    end
  end

  describe "pito:config:pane_title_length:get" do
    it "prints the default when the file is missing" do
      output = capture_stdout { invoke("pito:config:pane_title_length:get") }
      expect(output.strip).to eq("14")
    end
  end

  describe "pito:config:pane_title_length:set" do
    it "writes a valid integer in range" do
      output = capture_stdout { invoke("pito:config:pane_title_length:set", 18) }
      expect(output).to include("pane_title_length set to 18.")
      expect(YAML.safe_load_file(tmp_path)["pane_title_length"]).to eq(18)
    end

    it "rejects an out-of-range value" do
      output = capture_stdout { expect { invoke("pito:config:pane_title_length:set", 500) }.to raise_error(SystemExit) }
      expect(output).to include("out of range")
    end
  end

  describe "pito:config:timezone:get" do
    it "prints the default when the file is missing" do
      output = capture_stdout { invoke("pito:config:timezone:get") }
      expect(output.strip).to eq("UTC")
    end
  end

  describe "pito:config:timezone:set" do
    it "writes a valid IANA name" do
      output = capture_stdout { invoke("pito:config:timezone:set", "America/Los_Angeles") }
      expect(output).to include("timezone set to America/Los_Angeles.")
      expect(YAML.safe_load_file(tmp_path)["timezone"]).to eq("America/Los_Angeles")
    end

    it "rejects a bogus zone" do
      output = capture_stdout { expect { invoke("pito:config:timezone:set", "Bogus/Zone") }.to raise_error(SystemExit) }
      expect(output).to include("not a valid IANA")
    end
  end

  private

  def capture_stdout
    real = $stdout
    captured = StringIO.new
    $stdout = captured
    yield
    captured.string
  ensure
    $stdout = real
  end
end
