# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:totp", type: :rake do
  before(:all) { load_tasks }

  before { reenable("pito:totp") }

  it "outputs the otpauth URI" do
    expect { Rake::Task["pito:totp"].invoke }
      .to output(/otpauth:\/\/totp/).to_stdout
  end

  it "outputs the raw seed" do
    expect { Rake::Task["pito:totp"].invoke }
      .to output(/[A-Z2-7]{16,}/).to_stdout
  end

  it "outputs the /login instruction" do
    expect { Rake::Task["pito:totp"].invoke }
      .to output(%r{/login}).to_stdout
  end
end
