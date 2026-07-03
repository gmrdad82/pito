# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/jobs <subcommand> [arg]` — operator control over the
      # SolidQueue background-job system. Authenticated-only.
      #
      # Subcommands
      # ───────────
      # `/jobs` / `/jobs status`   — queue snapshot: process liveness, state
      #                              counts (ready/scheduled/claimed/failed),
      #                              paused queues, recurring schedule, and the
      #                              most-recent failures (with ids to requeue).
      # `/jobs requeue <id|all>`   — re-enqueue a failed job by SolidQueue::Job id
      #                              (the id shown in status), or every failure.
      # `/jobs run <key>`          — run a recurring task now (by its
      #                              config/recurring.yml key), without waiting
      #                              for its cron time.
      # `/jobs pause`              — pause processing on all known queues.
      # `/jobs resume`             — clear all queue pauses.
      # `/jobs --help`             — man page.
      #
      # Polymorphic args (subcommand + optional id/key) → `validates_own_arity`.
      # Each subcommand delegates to a `Pito::Jobs::*` service and wraps the
      # result as a `:system` event (or a `Result::Error`).
      class Jobs < Pito::Slash::Handler
        self.verb                 = :jobs
        self.description_key      = "pito.slash.jobs.descriptions.jobs"
        self.validates_own_arity  = true

        # Grammar (subcommand slot, auth): config/pito/verbs.yml (T8.9).

        SUBCOMMANDS = %w[status requeue run pause resume].freeze

        def call
          return show_help if help?

          case invocation.args.first.to_s.strip.downcase
          when "", "status" then show_status
          when "requeue"    then requeue
          when "run"        then run_recurring
          when "pause"      then pause
          when "resume"     then resume
          else                   unknown_subcommand
          end
        end

        def show_help
          body = Pito::MessageBuilder::ManPage.render(
            usage:  I18n.t("pito.slash.jobs.help.usage"),
            groups: [
              [ "Subcommands:", SUBCOMMANDS.map { |s| [ s, I18n.t("pito.slash.jobs.help.subcommands.#{s}") ] } ],
              [ "Options:",     [ [ "--help", "Print this help message" ] ] ]
            ]
          )
          man_ok(body)
        end

        private

        # ── status ──────────────────────────────────────────────────────────
        def show_status
          s     = Pito::Jobs::Status.call
          none  = I18n.t("pito.slash.jobs.status.none")
          label = ->(k) { I18n.t("pito.slash.jobs.status.labels.#{k}") }

          rows = [
            count_row(label.call(:processes), s[:processes], warn_when_zero: true),
            count_row(label.call(:ready),     s[:ready]),
            count_row(label.call(:scheduled), s[:scheduled]),
            count_row(label.call(:claimed),   s[:claimed]),
            count_row(label.call(:failed),    s[:failed], warn_when_positive: true),
            text_row(label.call(:paused),     s[:paused_queues].presence&.join(", ") || none),
            text_row(label.call(:recurring),  "#{s[:recurring].size}")
          ]

          # Append the most-recent failures with their ids so the operator can
          # `/jobs requeue <id>` straight from the status output.
          s[:recent_failed].each do |f|
            rows << {
              key:         "  ##{f[:id]}",
              value:       [ f[:job_class], f[:error] ].compact.join(" — "),
              key_class:   "text-red",
              value_class: "text-fg-dim"
            }
          end

          system_event(
            body:       I18n.t("pito.slash.jobs.status.section"),
            table_rows: rows
          )
        end

        # ── requeue ─────────────────────────────────────────────────────────
        def requeue
          target = invocation.args[1].to_s.strip
          return error("pito.slash.jobs.errors.requeue_missing_id") if target.blank?

          result = Pito::Jobs::RequeueFailed.call(target: target)
          return error("pito.slash.jobs.errors.requeue_not_found", id: target) if result == :not_found

          text_event(
            Pito::Copy.render(
              result == 1 ? "pito.copy.jobs.requeued_one" : "pito.copy.jobs.requeued",
              { count: result }
            )
          )
        end

        # ── run ─────────────────────────────────────────────────────────────
        def run_recurring
          key = invocation.args[1].to_s.strip
          return error("pito.slash.jobs.errors.run_missing_key") if key.blank?

          case (result = Pito::Jobs::RunRecurring.call(key: key))
          when :unknown
            error("pito.slash.jobs.errors.run_unknown", key: key)
          when :command_unsupported
            error("pito.slash.jobs.errors.run_command_unsupported", key: key)
          else
            text_event(Pito::Copy.render("pito.copy.jobs.ran", { job: result, key: key }))
          end
        end

        # ── pause / resume ────────────────────────────────────────────────────
        def pause
          paused = Pito::Jobs::PauseResume.call(action: :pause)
          key    = paused.empty? ? "pito.copy.jobs.paused_none" : "pito.copy.jobs.paused"
          text_event(Pito::Copy.render(key, { queues: paused.join(", ") }))
        end

        def resume
          count = Pito::Jobs::PauseResume.call(action: :resume)
          text_event(Pito::Copy.render("pito.copy.jobs.resumed", { count: count }))
        end

        def unknown_subcommand
          error("pito.slash.jobs.errors.unknown_subcommand",
                sub: invocation.args.first.to_s.strip)
        end

        # ── event/result helpers ──────────────────────────────────────────────
        def count_row(label, value, warn_when_zero: false, warn_when_positive: false)
          klass =
            if warn_when_zero    && value.to_i.zero?    then "text-red"
            elsif warn_when_positive && value.to_i.positive? then "text-red"
            else "text-green"
            end
          { key: "#{label}:", value: value.to_s, key_class: "text-fg-dim", value_class: klass }
        end

        def text_row(label, value)
          { key: "#{label}:", value: value.to_s, key_class: "text-fg-dim", value_class: "text-fg" }
        end

        def system_event(payload)
          Pito::Slash::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        def text_event(text)
          Pito::Slash::Result::Ok.new(events: [ { kind: :system, payload: { text: text } } ])
        end

        def man_ok(body)
          Pito::Slash::Result::Ok.new(events: [ { kind: :system, payload: { "html" => true, "body" => body } } ])
        end

        def error(message_key, **args)
          Pito::Slash::Result::Error.new(message_key: message_key, message_args: args)
        end
      end
    end
  end
end
