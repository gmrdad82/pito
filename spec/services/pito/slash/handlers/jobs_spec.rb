# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Jobs, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], kwargs: {}, raw: nil)
    invocation = Pito::Slash::Invocation.new(
      verb:   :jobs,
      args:   args,
      kwargs: kwargs,
      raw:    raw || "/jobs #{args.join(' ')}".strip
    )
    described_class.new(invocation:, conversation:)
  end

  # Build a real SolidQueue::Job + FailedExecution directly (the test ActiveJob
  # adapter doesn't write SolidQueue tables, so we seed the models).
  def create_failed_job(class_name: "BrokenJob", queue: "default")
    job = SolidQueue::Job.create!(queue_name: queue, class_name: class_name, arguments: { "args" => [] })
    SolidQueue::FailedExecution.create!(job: job, error: { "exception_class" => "RuntimeError", "message" => "boom" })
    job
  end

  describe "/jobs --help" do
    it "renders a man-page system event with the subcommands" do
      result = build_handler(raw: "/jobs --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      expect(payload["body"]).to include("pito-help-block").and include("status").and include("requeue")
    end
  end

  describe "/jobs status" do
    it "returns a system table with the queue-status section and a failed count" do
      create_failed_job
      result  = build_handler(args: [ "status" ]).call
      payload = result.events.first[:payload]

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(payload[:body]).to eq(I18n.t("pito.slash.jobs.status.section"))
      failed_row = payload[:table_rows].find { |r| r[:key] == "Failed:" }
      expect(failed_row[:value]).to eq("1")
      # The recent-failure row carries the job id so it can be requeued.
      expect(payload[:table_rows].any? { |r| r[:key].include?("#") }).to be(true)
    end

    it "treats bare /jobs as status" do
      result = build_handler(args: []).call
      expect(result.events.first[:payload][:body]).to eq(I18n.t("pito.slash.jobs.status.section"))
    end
  end

  describe "/jobs requeue" do
    it "requeues a failed job by id and clears the failure" do
      job = create_failed_job
      result = build_handler(args: [ "requeue", job.id.to_s ]).call

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(SolidQueue::FailedExecution.where(job_id: job.id)).to be_empty
    end

    it "requeues all failures" do
      create_failed_job
      create_failed_job
      build_handler(args: [ "requeue", "all" ]).call
      expect(SolidQueue::FailedExecution.count).to eq(0)
    end

    it "errors when the id has no failed execution" do
      result = build_handler(args: [ "requeue", "999999" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.jobs.errors.requeue_not_found")
    end

    it "errors when no id is given" do
      result = build_handler(args: [ "requeue" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.jobs.errors.requeue_missing_id")
    end
  end

  describe "/jobs run" do
    it "enqueues a recurring task's job class by key" do
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for)
        .with(:recurring).and_return({ nightly_sync: { class: "NightlySyncJob" } })

      result = nil
      expect { result = build_handler(args: [ "run", "nightly_sync" ]).call }
        .to have_enqueued_job(NightlySyncJob)

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to include("NightlySyncJob")
    end

    it "errors on an unknown key" do
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:recurring).and_return({})
      result = build_handler(args: [ "run", "nope" ]).call
      expect(result.message_key).to eq("pito.slash.jobs.errors.run_unknown")
    end

    it "errors when no key is given" do
      result = build_handler(args: [ "run" ]).call
      expect(result.message_key).to eq("pito.slash.jobs.errors.run_missing_key")
    end

    it "refuses a raw command task (no job class)" do
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for)
        .with(:recurring).and_return({ housekeeping: { command: "SolidQueue::Job.clear_finished_in_batches" } })
      result = build_handler(args: [ "run", "housekeeping" ]).call
      expect(result.message_key).to eq("pito.slash.jobs.errors.run_command_unsupported")
    end
  end

  describe "/jobs pause and resume" do
    it "pauses known queues then resumes (clears pauses)" do
      create_failed_job(queue: "default") # gives SolidQueue::Queue.all a queue to pause

      pause = build_handler(args: [ "pause" ]).call
      expect(pause).to be_a(Pito::Slash::Result::Ok)
      expect(SolidQueue::Pause.exists?(queue_name: "default")).to be(true)

      resume = build_handler(args: [ "resume" ]).call
      expect(resume).to be_a(Pito::Slash::Result::Ok)
      expect(SolidQueue::Pause.count).to eq(0)
    end
  end

  describe "unknown subcommand" do
    it "returns a usage error" do
      result = build_handler(args: [ "frobnicate" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.jobs.errors.unknown_subcommand")
    end
  end
end
