# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/jobs` (recognition only, all DB mocked) ─────────────────
#
# RULE: every subcommand/argument combination the handler recognises — no
# exception. All Pito::Jobs::* services are stubbed; zero SolidQueue model
# access, zero factories. No Conversation record created.
#
# Branches (source: app/services/pito/slash/handlers/jobs.rb #call):
#
#   1. help?                                 → show_help (man page)
#   2. args.first ∈ {"", "status"}           → show_status
#   3. args.first == "requeue"
#        args[1] blank                       → error :requeue_missing_id
#        RequeueFailed → :not_found          → error :requeue_not_found
#        RequeueFailed → Integer             → text_event (ok)
#   4. args.first == "run"
#        args[1] blank                       → error :run_missing_key
#        RunRecurring → :unknown             → error :run_unknown
#        RunRecurring → :command_unsupported → error :run_command_unsupported
#        RunRecurring → String               → text_event (ok)
#   5. args.first == "pause"
#        PauseResume → []                    → text_event (paused_none copy)
#        PauseResume → [names…]              → text_event (paused copy)
#   6. args.first == "resume"               → text_event (ok)
#   7. args.first ∈ anything else           → error :unknown_subcommand
#   8. Grammar/auth tier                    → :authenticated_only
#
# Case insensitivity: args.first is downcased before the case branch —
# e.g. "STATUS" routes to show_status, "REQUEUE" to requeue, etc.
#
# Notation:  * Result::Ok  = handler recognised the input and produced a value.
#            * Result::Error = handler recognised the input but rejected it with
#              a structured error (still a recognition outcome, not a parse miss).
RSpec.describe "Dispatch matrix — /jobs (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  # Build and invoke the handler directly, bypassing the dispatcher so we can
  # exercise every branch without routing concerns or auth interception.
  def call_handler(args: [], kwargs: {}, raw: nil, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :jobs,
      args:   args,
      kwargs: kwargs,
      raw:    raw || [ "/jobs", *args ].join(" ")
    )
    Pito::Slash::Handlers::Jobs.new(invocation:, conversation:, authenticated:).call
  end

  # ── Global stubs — overridden per-context where needed ────────────────────
  before do
    allow(Pito::Jobs::Status).to receive(:call).and_return(
      ready:         0,
      scheduled:     0,
      claimed:       0,
      failed:        0,
      processes:     1,
      paused_queues: [],
      recurring:     [],
      recent_failed: []
    )
    allow(Pito::Jobs::RequeueFailed).to receive(:call).and_return(1)
    allow(Pito::Jobs::RunRecurring).to  receive(:call).and_return("NightlySyncJob")
    allow(Pito::Jobs::PauseResume).to   receive(:call).and_return([])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    it "/jobs resolves to verb :jobs on the :slash stack (known)" do
      intent = parsed_intent("/jobs")
      expect(intent).to include(stack: :slash, verb: :jobs, known: true)
    end

    it "/jobs is gated as :authenticated_only" do
      expect(parsed_intent("/jobs")[:auth]).to eq(:authenticated_only)
    end

    it "/jobs status also resolves — the subcommand is a positional arg, not a separate verb" do
      intent = parsed_intent("/jobs status")
      expect(intent).to include(stack: :slash, verb: :jobs, known: true)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. --help intercept
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/jobs --help" do
    let(:result) { call_handler(raw: "/jobs --help") }

    it "returns Result::Ok (not an error)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits one system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload carries html: true (man-page flag)" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "body includes the pito-help-block container class" do
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end

    it "body lists every recognised subcommand" do
      body = result.events.first[:payload]["body"]
      Pito::Slash::Handlers::Jobs::SUBCOMMANDS.each do |sub|
        expect(body).to include(sub), "expected --help body to mention subcommand #{sub.inspect}"
      end
    end

    it "body includes the --help option itself" do
      expect(result.events.first[:payload]["body"]).to include("--help")
    end

    it "does not call any Pito::Jobs::* service (pure help, no side effects)" do
      result
      expect(Pito::Jobs::Status).not_to have_received(:call)
      expect(Pito::Jobs::RequeueFailed).not_to  have_received(:call)
      expect(Pito::Jobs::RunRecurring).not_to   have_received(:call)
      expect(Pito::Jobs::PauseResume).not_to    have_received(:call)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. show_status — bare /jobs and /jobs status
  # ═══════════════════════════════════════════════════════════════════════════
  describe "show_status (bare /jobs and /jobs status)" do
    shared_examples "a status event" do |description, args_val|
      context description do
        let(:result)  { call_handler(args: args_val) }
        let(:payload) { result.events.first[:payload] }

        it "returns Result::Ok" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
        end

        it "calls Pito::Jobs::Status.call exactly once" do
          result
          expect(Pito::Jobs::Status).to have_received(:call).once
        end

        it "emits a :system event (symbol kind)" do
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "payload[:body] equals the i18n section label" do
          expect(payload[:body]).to eq(I18n.t("pito.slash.jobs.status.section"))
        end

        it "payload[:table_rows] is a non-empty Array" do
          expect(payload[:table_rows]).to be_an(Array).and be_present
        end

        it "table_rows contains a Workers row" do
          labels = payload[:table_rows].map { |r| r[:key] }
          expect(labels).to include(I18n.t("pito.slash.jobs.status.labels.processes") + ":")
        end

        it "table_rows contains Ready / Scheduled / Running / Failed rows" do
          labels = payload[:table_rows].map { |r| r[:key] }
          %i[ready scheduled claimed failed].each do |k|
            expect(labels).to include(I18n.t("pito.slash.jobs.status.labels.#{k}") + ":")
          end
        end

        it "table_rows contains a Paused row" do
          labels = payload[:table_rows].map { |r| r[:key] }
          expect(labels).to include(I18n.t("pito.slash.jobs.status.labels.paused") + ":")
        end

        it "table_rows contains a Recurring row" do
          labels = payload[:table_rows].map { |r| r[:key] }
          expect(labels).to include(I18n.t("pito.slash.jobs.status.labels.recurring") + ":")
        end
      end
    end

    include_examples "a status event", "bare /jobs (args: [])",       []
    include_examples "a status event", '/jobs status (args: ["status"])', [ "status" ]
  end

  describe "show_status — case insensitivity" do
    it '"STATUS" (uppercase) routes to show_status' do
      result = call_handler(args: [ "STATUS" ])
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:body]).to eq(I18n.t("pito.slash.jobs.status.section"))
    end

    it '"Status" (mixed case) routes to show_status' do
      expect(call_handler(args: [ "Status" ])).to be_a(Pito::Slash::Result::Ok)
    end
  end

  describe "show_status — count/colour encoding" do
    context "processes count is zero" do
      before do
        allow(Pito::Jobs::Status).to receive(:call).and_return(
          ready: 0, scheduled: 0, claimed: 0, failed: 0,
          processes: 0, paused_queues: [], recurring: [], recent_failed: []
        )
      end

      it "Workers row value_class is text-red (zero workers = warning)" do
        rows = call_handler.events.first[:payload][:table_rows]
        workers_row = rows.find { |r| r[:key].start_with?(I18n.t("pito.slash.jobs.status.labels.processes")) }
        expect(workers_row[:value_class]).to eq("text-red")
      end
    end

    context "failed count is positive" do
      before do
        allow(Pito::Jobs::Status).to receive(:call).and_return(
          ready: 0, scheduled: 0, claimed: 0, failed: 3,
          processes: 1, paused_queues: [], recurring: [], recent_failed: []
        )
      end

      it "Failed row value_class is text-red (positive failed = warning)" do
        rows = call_handler.events.first[:payload][:table_rows]
        failed_row = rows.find { |r| r[:key].start_with?(I18n.t("pito.slash.jobs.status.labels.failed")) }
        expect(failed_row[:value_class]).to eq("text-red")
      end
    end

    context "healthy queue (processes>0, failed=0)" do
      it "Workers row value_class is text-green" do
        rows = call_handler.events.first[:payload][:table_rows]
        workers_row = rows.find { |r| r[:key].start_with?(I18n.t("pito.slash.jobs.status.labels.processes")) }
        expect(workers_row[:value_class]).to eq("text-green")
      end
    end
  end

  describe "show_status — recent_failed rows" do
    before do
      allow(Pito::Jobs::Status).to receive(:call).and_return(
        ready: 0, scheduled: 0, claimed: 0, failed: 2,
        processes: 1, paused_queues: [], recurring: [],
        recent_failed: [
          { id: 101, job_class: "BrokenJob",  error: "boom"  },
          { id: 102, job_class: "AnotherJob", error: nil     }
        ]
      )
    end

    it "appends one extra row per recent failure" do
      rows = call_handler.events.first[:payload][:table_rows]
      expect(rows.count { |r| r[:key].include?("#") }).to eq(2)
    end

    it "failure row key contains the job id prefixed with #" do
      rows = call_handler.events.first[:payload][:table_rows]
      expect(rows.any? { |r| r[:key].include?("#101") }).to be(true)
      expect(rows.any? { |r| r[:key].include?("#102") }).to be(true)
    end

    it "failure row value contains the job class name" do
      rows = call_handler.events.first[:payload][:table_rows]
      broken_row = rows.find { |r| r[:key].include?("#101") }
      expect(broken_row[:value]).to include("BrokenJob")
    end

    it "failure row value includes the error message when present" do
      rows = call_handler.events.first[:payload][:table_rows]
      broken_row = rows.find { |r| r[:key].include?("#101") }
      expect(broken_row[:value]).to include("boom")
    end

    it "failure row has key_class text-red for conspicuity" do
      rows = call_handler.events.first[:payload][:table_rows]
      rows.select { |r| r[:key].start_with?("  #") }.each do |r|
        expect(r[:key_class]).to eq("text-red")
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. requeue
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/jobs requeue" do
    context "no target argument (args: ['requeue'])" do
      it "returns Result::Error" do
        expect(call_handler(args: [ "requeue" ])).to be_a(Pito::Slash::Result::Error)
      end

      it "message_key is requeue_missing_id" do
        expect(call_handler(args: [ "requeue" ]).message_key)
          .to eq("pito.slash.jobs.errors.requeue_missing_id")
      end

      it "does not call RequeueFailed" do
        call_handler(args: [ "requeue" ])
        expect(Pito::Jobs::RequeueFailed).not_to have_received(:call)
      end
    end

    context "target is a specific id and job is found (RequeueFailed → 1)" do
      before { allow(Pito::Jobs::RequeueFailed).to receive(:call).with(target: "42").and_return(1) }

      it "returns Result::Ok" do
        expect(call_handler(args: %w[requeue 42])).to be_a(Pito::Slash::Result::Ok)
      end

      it "calls RequeueFailed with the exact id string" do
        call_handler(args: %w[requeue 42])
        expect(Pito::Jobs::RequeueFailed).to have_received(:call).with(target: "42")
      end

      it "emits a system text event" do
        result = call_handler(args: %w[requeue 42])
        expect(result.events.first[:payload]).to have_key(:text)
      end
    end

    context "target is 'all' and multiple jobs exist (RequeueFailed → 3)" do
      before { allow(Pito::Jobs::RequeueFailed).to receive(:call).with(target: "all").and_return(3) }

      it "returns Result::Ok" do
        expect(call_handler(args: %w[requeue all])).to be_a(Pito::Slash::Result::Ok)
      end

      it "calls RequeueFailed with target 'all'" do
        call_handler(args: %w[requeue all])
        expect(Pito::Jobs::RequeueFailed).to have_received(:call).with(target: "all")
      end
    end

    context "target id is not found (RequeueFailed → :not_found)" do
      before { allow(Pito::Jobs::RequeueFailed).to receive(:call).and_return(:not_found) }

      it "returns Result::Error" do
        expect(call_handler(args: %w[requeue 9999])).to be_a(Pito::Slash::Result::Error)
      end

      it "message_key is requeue_not_found" do
        expect(call_handler(args: %w[requeue 9999]).message_key)
          .to eq("pito.slash.jobs.errors.requeue_not_found")
      end

      it "message_args[:id] echoes the requested id" do
        expect(call_handler(args: %w[requeue 9999]).message_args[:id]).to eq("9999")
      end
    end

    context "case insensitivity — 'REQUEUE' routes to the requeue branch" do
      before { allow(Pito::Jobs::RequeueFailed).to receive(:call).with(target: "42").and_return(1) }

      it "returns Result::Ok (not unknown_subcommand)" do
        expect(call_handler(args: %w[REQUEUE 42])).to be_a(Pito::Slash::Result::Ok)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. run
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/jobs run" do
    context "no key argument (args: ['run'])" do
      it "returns Result::Error" do
        expect(call_handler(args: [ "run" ])).to be_a(Pito::Slash::Result::Error)
      end

      it "message_key is run_missing_key" do
        expect(call_handler(args: [ "run" ]).message_key)
          .to eq("pito.slash.jobs.errors.run_missing_key")
      end

      it "does not call RunRecurring" do
        call_handler(args: [ "run" ])
        expect(Pito::Jobs::RunRecurring).not_to have_received(:call)
      end
    end

    context "key resolves to a known job class (RunRecurring → String)" do
      before { allow(Pito::Jobs::RunRecurring).to receive(:call).with(key: "nightly_sync").and_return("NightlySyncJob") }

      it "returns Result::Ok" do
        expect(call_handler(args: %w[run nightly_sync])).to be_a(Pito::Slash::Result::Ok)
      end

      it "calls RunRecurring with the given key string" do
        call_handler(args: %w[run nightly_sync])
        expect(Pito::Jobs::RunRecurring).to have_received(:call).with(key: "nightly_sync")
      end

      it "event text includes the job class name" do
        text = call_handler(args: %w[run nightly_sync]).events.first[:payload][:text]
        expect(text).to include("NightlySyncJob")
      end

      it "event text includes the recurring key" do
        text = call_handler(args: %w[run nightly_sync]).events.first[:payload][:text]
        expect(text).to include("nightly_sync")
      end
    end

    context "key is unknown (RunRecurring → :unknown)" do
      before { allow(Pito::Jobs::RunRecurring).to receive(:call).and_return(:unknown) }

      it "returns Result::Error" do
        expect(call_handler(args: %w[run bogus_key])).to be_a(Pito::Slash::Result::Error)
      end

      it "message_key is run_unknown" do
        expect(call_handler(args: %w[run bogus_key]).message_key)
          .to eq("pito.slash.jobs.errors.run_unknown")
      end

      it "message_args[:key] echoes the requested key" do
        expect(call_handler(args: %w[run bogus_key]).message_args[:key]).to eq("bogus_key")
      end
    end

    context "task is a raw command with no job class (RunRecurring → :command_unsupported)" do
      before { allow(Pito::Jobs::RunRecurring).to receive(:call).and_return(:command_unsupported) }

      it "returns Result::Error" do
        expect(call_handler(args: %w[run housekeeping])).to be_a(Pito::Slash::Result::Error)
      end

      it "message_key is run_command_unsupported" do
        expect(call_handler(args: %w[run housekeeping]).message_key)
          .to eq("pito.slash.jobs.errors.run_command_unsupported")
      end

      it "message_args[:key] echoes the requested key" do
        expect(call_handler(args: %w[run housekeeping]).message_args[:key]).to eq("housekeeping")
      end
    end

    context "case insensitivity — 'RUN' routes to run_recurring" do
      before { allow(Pito::Jobs::RunRecurring).to receive(:call).with(key: "nightly").and_return("NightlyJob") }

      it "returns Result::Ok (not unknown_subcommand)" do
        expect(call_handler(args: %w[RUN nightly])).to be_a(Pito::Slash::Result::Ok)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. pause
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/jobs pause" do
    context "no active queues exist (PauseResume → [])" do
      before { allow(Pito::Jobs::PauseResume).to receive(:call).with(action: :pause).and_return([]) }

      it "returns Result::Ok" do
        expect(call_handler(args: [ "pause" ])).to be_a(Pito::Slash::Result::Ok)
      end

      it "calls PauseResume with action: :pause" do
        call_handler(args: [ "pause" ])
        expect(Pito::Jobs::PauseResume).to have_received(:call).with(action: :pause)
      end

      it "event text comes from the paused_none copy key (nothing to pause)" do
        text = call_handler(args: [ "pause" ]).events.first[:payload][:text]
        expect(text).to include(Pito::Copy.render("pito.copy.jobs.paused_none"))
      end
    end

    context "active queues exist (PauseResume → ['default', 'critical'])" do
      before { allow(Pito::Jobs::PauseResume).to receive(:call).with(action: :pause).and_return(%w[default critical]) }

      it "returns Result::Ok" do
        expect(call_handler(args: [ "pause" ])).to be_a(Pito::Slash::Result::Ok)
      end

      it "event text lists the paused queue names" do
        text = call_handler(args: [ "pause" ]).events.first[:payload][:text]
        expect(text).to include("default").and include("critical")
      end
    end

    context "case insensitivity — 'PAUSE' routes to pause" do
      before { allow(Pito::Jobs::PauseResume).to receive(:call).with(action: :pause).and_return([]) }

      it "returns Result::Ok (not unknown_subcommand)" do
        expect(call_handler(args: [ "PAUSE" ])).to be_a(Pito::Slash::Result::Ok)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. resume
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/jobs resume" do
    before { allow(Pito::Jobs::PauseResume).to receive(:call).with(action: :resume).and_return(2) }

    it "returns Result::Ok" do
      expect(call_handler(args: [ "resume" ])).to be_a(Pito::Slash::Result::Ok)
    end

    it "calls PauseResume with action: :resume" do
      call_handler(args: [ "resume" ])
      expect(Pito::Jobs::PauseResume).to have_received(:call).with(action: :resume)
    end

    it "does not call Status, RequeueFailed, or RunRecurring" do
      call_handler(args: [ "resume" ])
      expect(Pito::Jobs::Status).not_to have_received(:call)
      expect(Pito::Jobs::RequeueFailed).not_to  have_received(:call)
      expect(Pito::Jobs::RunRecurring).not_to   have_received(:call)
    end

    it "emits a system text event" do
      result = call_handler(args: [ "resume" ])
      expect(result.events.first[:payload]).to have_key(:text)
    end

    context "case insensitivity — 'RESUME' routes to resume" do
      it "returns Result::Ok (not unknown_subcommand)" do
        expect(call_handler(args: [ "RESUME" ])).to be_a(Pito::Slash::Result::Ok)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 7. unknown_subcommand — every unrecognised first arg
  # ═══════════════════════════════════════════════════════════════════════════
  describe "unknown subcommand" do
    # These words are NOT in the handler's case branches. Each should produce
    # error :unknown_subcommand — if any of them accidentally return :ok it
    # indicates a RECOGNITION BUG to report (not fix).
    [
      "frobnicate",
      "list",      # plausible alias but not implemented
      "clear",     # mentioned in user-visible help for other tools, not this one
      "retry",     # SolidQueue concept but not a /jobs subcommand
      "queue",     # partial match — not implemented
      "flush",     # not implemented
      "stats"      # alias for another verb in chat, not a jobs subcommand
    ].each do |sub|
      context "subcommand #{sub.inspect}" do
        let(:result) { call_handler(args: [ sub ]) }

        it "returns Result::Error" do
          expect(result).to be_a(Pito::Slash::Result::Error)
        end

        it "message_key is unknown_subcommand" do
          expect(result.message_key).to eq("pito.slash.jobs.errors.unknown_subcommand")
        end

        it "message_args[:sub] echoes the raw (un-downcased) subcommand" do
          # The handler does: sub: invocation.args.first.to_s.strip  (no downcase)
          expect(result.message_args[:sub]).to eq(sub)
        end
      end
    end

    it "does not call any Pito::Jobs::* service for an unknown subcommand" do
      call_handler(args: [ "frobnicate" ])
      expect(Pito::Jobs::Status).not_to have_received(:call)
      expect(Pito::Jobs::RequeueFailed).not_to  have_received(:call)
      expect(Pito::Jobs::RunRecurring).not_to   have_received(:call)
      expect(Pito::Jobs::PauseResume).not_to    have_received(:call)
    end
  end
end
