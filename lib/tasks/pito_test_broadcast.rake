namespace :pito do
  desc "Push dummy Sidekiq jobs for status bar testing"
  task test_broadcast: :environment do
    puts "Pushing dummy Sidekiq jobs..."

    # Busy: simulate active (long-running) jobs
    3.times do
      Pito::Test::SimpleSidekiqJob.perform_async
      print "."
    end

    # Enqueued: queue some jobs that will wait
    5.times do
      Pito::Test::SimpleSidekiqJob.perform_in(rand(10..60).seconds)
      print "."
    end

    puts
    puts "Done! Watch the status bar — b/e/r/d will update as jobs run."
  end
end
