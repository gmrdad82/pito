# frozen_string_literal: true

require "rails_helper"

# Guard against the "tests green, browser broken" class of bug: a JS module that
# imports `from "pito/foo"` will fail to load in the real browser (bare-specifier
# resolution) unless `pito/foo` is pinned in config/importmap.rb. vitest/Vite
# resolve by file path and never exercise importmap, so this is the only place
# that catches an unpinned module. (Historically caught a missing pin that left a
# module dead in the browser while every test passed.)
RSpec.describe "importmap pin coverage" do
  it "pins every pito/* module imported anywhere in app/javascript" do
    imported = Dir.glob(Rails.root.join("app/javascript/**/*.js")).flat_map do |file|
      File.read(file).scan(/from\s+["']pito\/([a-z0-9_]+)["']/i).flatten
    end.uniq

    importmap = File.read(Rails.root.join("config/importmap.rb"))
    pinned = importmap.scan(/pin\s+["']pito\/([a-z0-9_]+)["']/i).flatten

    missing = imported - pinned
    expect(missing).to be_empty,
      "Unpinned pito/* modules — these import fine in vitest but FAIL in the browser:\n" \
      "  #{missing.join(', ')}\nAdd a `pin \"pito/<name>\", to: \"pito/<name>.js\"` to config/importmap.rb."
  end
end
