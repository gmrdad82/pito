namespace :pito do
  desc "Push dummy Sidekiq jobs for status bar testing"
  task test_broadcast: :environment do
    puts "Pushing dummy Sidekiq jobs..."

    # Busy: long-running jobs (30s sleep)
    2.times do
      Pito::Test::SimpleSidekiqJob.perform_async(30)
      print "b"
    end

    # Enqueued: immediate jobs that will sit in queue
    12.times do
      Pito::Test::SimpleSidekiqJob.perform_async(rand(1..3))
      print "e"
    end

    # Retry: a job that fails and goes to retry
    2.times do
      Pito::Test::FailingJob.perform_async
      print "r"
    end

    # Dead: a job with max retries exhausted will go to dead
    # (handled by Sidekiq automatically)

    puts
    puts "Done! b=busy, e=enqueued, r=retry"
    puts "Watch the status bar — b/e/r/d will update as jobs run."
  end
end
