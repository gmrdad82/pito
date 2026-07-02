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

  # Loads all rake tasks once per suite — GUARDED: a second load_tasks call
  # (each rake spec file calls it in before(:all)) would ENHANCE every task
  # with a duplicate body, so invoking a task would run it twice.
  def load_tasks
    return if RakeSpecHelper.tasks_loaded

    Rails.application.load_tasks
    RakeSpecHelper.tasks_loaded = true
  end

  class << self
    attr_accessor :tasks_loaded
  end

  # Re-enables a rake task so it can be invoked multiple times in one spec.
  def reenable(task_name)
    Rake::Task[task_name].reenable
  end
end

RSpec.configure do |config|
  config.include RakeSpecHelper, type: :rake
end
