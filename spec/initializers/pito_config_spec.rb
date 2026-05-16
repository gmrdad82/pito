require "rails_helper"

# Phase 29 (settings refactor) — `config/initializers/pito_config.rb`
# loader test.
#
# Boot already happened by the time we get here, so
# `Rails.application.config.x.pito` is populated from the live
# `config/pito.yml` file. These specs target the `Pito::Config.load!`
# class method directly: redirect `PATH` to a per-spec temp file,
# call `load!`, and assert on the returned hash.
RSpec.describe "Pito::Config loader" do
  let(:tmp_path) do
    Pathname.new(Dir.mktmpdir).join("pito.yml")
  end

  before { stub_const("Pito::Config::PATH", tmp_path) }

  after do
    File.delete(tmp_path) if File.exist?(tmp_path)
    FileUtils.rm_rf(tmp_path.dirname) if File.directory?(tmp_path.dirname)
  end

  describe ".load!" do
    it "returns defaults when the file is absent" do
      result = Pito::Config.load!
      expect(result).to eq(
        "max_panes" => 3,
        "pane_title_length" => 14,
        "timezone" => "UTC"
      )
    end

    it "returns the file's values when valid" do
      File.write(tmp_path, { "max_panes" => 6, "pane_title_length" => 22, "timezone" => "Europe/Bucharest" }.to_yaml)
      result = Pito::Config.load!
      expect(result["max_panes"]).to eq(6)
      expect(result["pane_title_length"]).to eq(22)
      expect(result["timezone"]).to eq("Europe/Bucharest")
    end

    it "falls back to defaults on out-of-range integers" do
      File.write(tmp_path, { "max_panes" => 99, "pane_title_length" => 2 }.to_yaml)
      result = Pito::Config.load!
      expect(result["max_panes"]).to eq(3)
      expect(result["pane_title_length"]).to eq(14)
    end

    it "falls back to defaults on non-integer entries" do
      File.write(tmp_path, { "max_panes" => "abc", "pane_title_length" => nil }.to_yaml)
      result = Pito::Config.load!
      expect(result["max_panes"]).to eq(3)
      expect(result["pane_title_length"]).to eq(14)
    end

    it "falls back to the default timezone on a bogus IANA name" do
      File.write(tmp_path, { "timezone" => "Bogus/Zone" }.to_yaml)
      result = Pito::Config.load!
      expect(result["timezone"]).to eq("UTC")
    end

    it "tolerates an unparseable YAML payload (returns defaults)" do
      File.write(tmp_path, "max_panes: : : :")
      result = Pito::Config.load!
      expect(result["max_panes"]).to eq(3)
    end

    it "treats partial files gracefully (mixes file values + defaults)" do
      File.write(tmp_path, { "max_panes" => 7 }.to_yaml)
      result = Pito::Config.load!
      expect(result["max_panes"]).to eq(7)
      expect(result["pane_title_length"]).to eq(14)
      expect(result["timezone"]).to eq("UTC")
    end
  end

  describe "Rails.application.config.x.pito" do
    # The boot-time values come from `config/pito.yml`. We don't
    # mutate them here; assert the keys exist + are populated with
    # sensible types so a regression in the initializer surface
    # surfaces.
    it "carries an integer max_panes" do
      expect(Rails.application.config.x.pito.max_panes).to be_a(Integer)
      expect(Rails.application.config.x.pito.max_panes).to be_between(1, 10)
    end

    it "carries an integer pane_title_length" do
      expect(Rails.application.config.x.pito.pane_title_length).to be_a(Integer)
      expect(Rails.application.config.x.pito.pane_title_length).to be_between(6, 50)
    end

    it "carries a valid IANA timezone" do
      tz = Rails.application.config.x.pito.timezone
      expect(tz).to be_a(String)
      expect(ActiveSupport::TimeZone[tz]).not_to be_nil
    end
  end
end
