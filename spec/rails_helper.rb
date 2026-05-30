# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
# Force the test environment. A plain `||=` would let an ambient
# RAILS_ENV=development (exported in the dev shell) leak in and boot specs
# against the dev environment — which silently breaks host authorization
# (Rack::Test's www.example.com isn't in the dev config.hosts allowlist).
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
require 'factory_bot_rails'
# Add additional requires below this line. Rails is not loaded until this point!

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
