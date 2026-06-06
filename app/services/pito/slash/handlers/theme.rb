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
      # `/themes list` / `ls`   — placeholder (full System message in P7).
      # `/themes`  (bare)       — placeholder (sidebar in P8).
      # `/themes <unknown>`     — witty error pointing to `/themes list`.
      # `/themes --help`        — per-command usage + grouped theme list.
      #
      # The `name` arg accepts any registered slug OR the special token "default"
      # (→ Registry.default). Resolution is delegated to Registry.resolve_target.
      #
      # ALIAS SURFACE  (`ls` ≡ `list`)
      # ────────────────────────────────
      # Subcommand aliasing is implemented via the `:theme_subcommands` vocabulary
      # synonym mechanism (see Pito::Grammar::Vocabularies::THEME_SUBCOMMANDS).
      # `first_arg` is resolved through that vocabulary before dispatch, so `"ls"`
      # canonicalizes to `"list"` and the case statement sees only canonical names.
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
        # `/themes` is valid (→ sidebar placeholder).
        grammar do
          enum :subcommand, source: :theme_names, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.theme"
        end

        # Canonical subcommand keywords.  `ls` is NOT listed here because it is
        # a synonym resolved to `list` by THEME_SUBCOMMANDS before dispatch.
        # Autocomplete suggests canonical names only (`list`); `ls` is
        # hidden-but-accepted — it works but won't appear in the palette.
        SUBCOMMANDS = %w[list preview apply reset].freeze

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
          when ""        then placeholder_sidebar
          when "list"    then list_themes
          when "preview" then dispatch_preview
          when "apply"   then dispatch_apply
          when "reset"   then dispatch_reset
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

        # ── list ──────────────────────────────────────────────────────────────

        # Emits a System message with Dark/Light sections, current theme marked.
        # The message is stamped as follow-up-able (reply_target: "theme_list") so
        # the user can reply `#<handle> preview <name>` / `#<handle> apply <name>`.
        # The old `theme_list: true` flag and the "most-recent list" heuristic are
        # replaced by the unique-handle routing provided by the follow-up engine.
        def list_themes
          grouped      = Pito::Themes::Registry.grouped
          current_slug = AppSetting.theme

          dark_rows  = build_theme_rows(grouped[:dark]  || [], current_slug)
          light_rows = build_theme_rows(grouped[:light] || [], current_slug)

          payload = {
            body:     Pito::Copy.render("pito.copy.theme.list_intro"),
            sections: [
              { title: I18n.t("pito.slash.theme.list.dark_header"),  rows: dark_rows },
              { title: I18n.t("pito.slash.theme.list.light_header"), rows: light_rows }
            ]
          }
          Pito::FollowUp.make_followupable!(payload, target: "theme_list", conversation:)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: payload
            }
          ])
        end

        # Build kv rows for a group of theme definitions. The current theme is
        # marked with a "← this one" suffix on the right (no leading bullet).
        def build_theme_rows(definitions, current_slug)
          definitions.map do |d|
            value = d.label
            if d.slug == current_slug
              marker = Pito::Copy.render("pito.copy.theme.current_marker")
              value  = "#{d.label}   #{marker}"
            end
            { key: d.slug, value: value }
          end
        end

        def placeholder_sidebar
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: Pito::Copy.render("pito.copy.theme.sidebar_placeholder")
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
