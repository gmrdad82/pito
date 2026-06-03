# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:tools:totp", type: :rake do
  before(:all) { load_tasks }

  before { reenable("pito:tools:totp") }

  it "outputs the otpauth URI" do
    expect { Rake::Task["pito:tools:totp"].invoke }
      .to output(/otpauth:\/\/totp/).to_stdout
  end

  it "outputs the raw seed" do
    expect { Rake::Task["pito:tools:totp"].invoke }
      .to output(/[A-Z2-7]{16,}/).to_stdout
  end

  it "outputs the /login instruction" do
    expect { Rake::Task["pito:tools:totp"].invoke }
      .to output(%r{/login}).to_stdout
  end
end
