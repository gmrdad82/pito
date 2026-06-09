# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/themes [subcommand] [name]`.
      #
      # Subcommands / dispatch table
      # ─────────────────────────────
      # `/themes apply <name>`  — persist + broadcast; also bare `/themes <name>`.
      # `/themes preview <name>`— broadcast only (no persist); System message with
      #                           apply/revert hints. Preview-vs-apply rule:
      #                           preview does NOT write AppSetting; it only sends
      #                           the set-theme Turbo Stream so the current tab
      #                           recolors immediately. The caller must explicitly
      #                           run `/themes apply <name>` or `/themes reset` to
      #                           make the change permanent.
      # `/themes reset`         — apply the registry default (tokyo-night) + confirm.
      # `/themes`  (bare)       — opens the theme picker Sidebar.
      # `/themes <unknown>`     — witty error pointing to `/themes --help`.
      # `/themes --help`        — per-command usage + grouped theme list.
      #
      # The `name` arg accepts any registered slug OR the special token "default"
      # (→ Registry.default). Resolution is delegated to Registry.resolve_target.
      #
      # ALIAS SURFACE  (`ls` ≡ `list` — retained for backward compat but `list`
      # ────────────────────────────────  now falls through to the Sidebar path)
      # Subcommand aliasing is implemented via the `:theme_subcommands` vocabulary
      # synonym mechanism (see Pito::Grammar::Vocabularies::THEME_SUBCOMMANDS).
      # `first_arg` is resolved through that vocabulary before dispatch.
      #
      # WHY vocabulary synonyms?
      #   Spec.aliases maps alternative *verb* names to a Spec (verb-level routing).
      #   Subcommands are *values* inside invocation.args, not verbs.  Using a
      #   Vocabulary with synonyms is the production-correct layer: it's already
      #   used by every enum/literal slot in the grammar engine for the same purpose
      #   (e.g. "fps" → "Shooter", "ps5" → "PlayStation 5").  The synonym is
      #   declared once in the vocabulary constant; the handler, grammar, and
      #   autocomplete engine need no special-case logic.  Future commands add
      #   subcommand aliases by declaring their own static vocabulary.
      class Theme < Pito::Slash::Handler
        self.verb        = :themes
        self.description_key = "pito.slash.theme.descriptions.theme"

        # The first positional arg is polymorphic — it may be a subcommand keyword
        # (list/ls/preview/apply/reset) OR a bare theme name (shorthand apply).
        # The generic dispatcher arity guard cannot model this, so we opt out and
        # validate arity ourselves inside #call.
        self.validates_own_arity = true

        # Grammar: first positional arg is either a subcommand keyword or a theme
        # name from the :theme_names vocab. Both slots are optional so bare
        # `/themes` is valid (→ Sidebar).
        grammar do
          enum :subcommand, source: :theme_names, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.theme"
        end

        # Canonical subcommand keywords.  `ls` is NOT listed here because it is
        # a synonym resolved to `list` by THEME_SUBCOMMANDS before dispatch.
        SUBCOMMANDS = %w[preview apply reset].freeze

        # Vocabulary used to canonicalize the first arg before dispatch.
        # Resolves synonyms such as "ls" → "list".
        SUBCOMMAND_VOCAB = Pito::Grammar::Vocabularies::THEME_SUBCOMMANDS

        def call
          return show_help if help?

          # Self-validation: /themes accepts 0, 1, or 2 args (preview/apply + name).
          # 3+ args are always too many. 2 args are only valid when the first is
          # preview or apply and the second resolves to a theme.
          return too_many_args_error if invocation.args.size >= 3

          raw_arg   = invocation.args.first.to_s.strip.downcase
          first_arg = SUBCOMMAND_VOCAB.resolve(raw_arg) || raw_arg

          if invocation.args.size == 2
            # 2-arg form: first must be `preview` or `apply`.
            unless %w[preview apply].include?(first_arg)
              return too_many_args_error
            end
          end

          case first_arg
          when "", "list" then open_sidebar
          when "preview"  then dispatch_preview
          when "apply"    then dispatch_apply
          when "reset"    then dispatch_reset
          else
            # Bare theme name (shorthand apply) or unknown target.
            definition = Pito::Themes::Registry.resolve_target(first_arg)
            definition ? apply(definition) : unknown_target(first_arg)
          end
        end

        # `/themes --help` — usage + grouped theme list.
        def show_help
          grouped = Pito::Themes::Registry.grouped

          dark_rows  = (grouped[:dark]  || []).map { |d| { key: d.slug, value: d.label } }
          light_rows = (grouped[:light] || []).map { |d| { key: d.slug, value: d.label } }

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       I18n.t("pito.slash.theme.help.usage"),
                table_rows: [
                  { key: "──── Dark ────",  value: "" },
                  *dark_rows,
                  { key: "──── Light ───", value: "" },
                  *light_rows
                ],
                info_lines: [ I18n.t("pito.slash.theme.help.description") ]
              }
            }
          ])
        end

        private

        # ── Dispatch helpers ──────────────────────────────────────────────────

        def dispatch_preview
          name = invocation.args[1].to_s.strip.downcase
          if name.empty?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.theme.errors.missing_name_for_preview",
              message_args: {}
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)
          return unknown_target(name) unless definition

          preview(definition)
        end

        def dispatch_apply
          name = invocation.args[1].to_s.strip.downcase
          if name.empty?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.theme.errors.missing_name_for_apply",
              message_args: {}
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)
          return unknown_target(name) unless definition

          apply(definition)
        end

        def dispatch_reset
          Pito::Slash::Result::Ok.new(events: Pito::Themes::Switch.reset)
        end

        # ── apply ─────────────────────────────────────────────────────────────

        # Delegates to Pito::Themes::Switch.apply for persist + broadcast.
        # @param definition [Pito::Themes::Definition]
        # @param reset [Boolean] use the reset confirmation string instead of apply
        def apply(definition, reset: false)
          Pito::Slash::Result::Ok.new(events: Pito::Themes::Switch.apply(definition, reset:))
        end

        # ── preview ───────────────────────────────────────────────────────────

        # Delegates to Pito::Themes::Switch.preview (broadcast only, no persist).
        def preview(definition)
          Pito::Slash::Result::Ok.new(events: Pito::Themes::Switch.preview(definition))
        end

        # ── sidebar ───────────────────────────────────────────────────────────

        # Opens the theme picker Sidebar (Turbo Stream into #pito-sidebar).
        # Bare `/themes`, `/themes list`, and `/themes ls` all route here.
        # The controller fast-path intercepts these before the async pipeline;
        # this method is the fallback for the job path (e.g. test harness).
        def open_sidebar
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                sidebar_open: "theme",
                text:         I18n.t("pito.slash.theme.sidebar.opening")
              }
            }
          ])
        end

        # ── error ─────────────────────────────────────────────────────────────

        def unknown_target(name)
          Pito::Slash::Result::Error.new(
            message_key:  "pito.slash.theme.errors.unknown_target",
            message_args: { name: name }
          )
        end

        def too_many_args_error
          Pito::Slash::Result::Error.new(
            message_key:  "pito.slash.theme.errors.too_many_args",
            message_args: {}
          )
        end
      end
    end
  end
end
