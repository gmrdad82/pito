# frozen_string_literal: true

# Shared helpers for rake task specs.
module RakeSpecHelper
  # Suppresses both stdout and stderr during the block.
  # Use for tasks that print status messages you don't want leaking
  # into the test output.
  def suppress_output
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = File.open(File::NULL, "w")
    $stderr = File.open(File::NULL, "w")
    yield
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end

  # Loads all rake tasks once per suite.
  def load_tasks
    Rails.application.load_tasks
  end

  # Re-enables a rake task so it can be invoked multiple times in one spec.
  def reenable(task_name)
    Rake::Task[task_name].reenable
  end
end

RSpec.configure do |config|
  config.include RakeSpecHelper, type: :rake
end
