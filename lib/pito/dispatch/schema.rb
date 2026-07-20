# frozen_string_literal: true

module Pito
  module Dispatch
    # Schema — the structural + vocabulary contract for config/pito/tools.yml.
    #
    # `Pito::Dispatch::Config` LOADS + freezes the file; `Schema` says whether the
    # loaded document is *well-formed*. It is the single source of truth for "what
    # shape may a tool entry take", so a future tool author who mistypes a key or
    # invents an option gets a precise, path-named error instead of a silent
    # mis-parse. The schema-integrity suite (spec/dispatch/schema_integrity_spec.rb)
    # runs `validate` over the real, frozen `Config.data`, then resolves every
    # reference this pure-structural pass cannot see (constants, copy keys,
    # registries, segment parity).
    #
    # Design:
    #   * UNKNOWN KEYS ARE REJECTED — every level carries an explicit allow-list; an
    #     unexpected key is an error naming the exact dotted path, with a
    #     did-you-mean suggestion on near-misses (Levenshtein ≤ 2). Example:
    #       tools.show.reply.targets.game_list.mod: unknown key (did you mean mode?)
    #   * VALUES ARE TYPED / ENUMERATED — modes, kinds, auth tiers, slot kinds,
    #     entities, and the predicate / resolver / client-action names are closed
    #     sets. The document is READ, never mutated (works on frozen hashes).
    #
    # `validate(doc) -> Array<Error>` returns [] for a valid document; each Error
    # carries `path` + `message` and renders as "path: message". `alias_collisions`
    # is a separate cross-cutting pass: within one dispatch namespace (chat / slash
    # / reply) no token may map to two tools.
    module Schema
      # ── Allowed keys, per level (unknown key ⇒ rejected) ──────────────────────
      TOP_KEYS             = %i[schema_version universal_reply vocabularies tools mcp_readers nl].freeze
      VOCAB_KEYS           = %i[members synonyms fillers resolver].freeze
      UNIVERSAL_KEYS       = %i[mode aliases kinds except].freeze
      TOOL_KEYS            = %i[aliases description availability enabled_if auth internal universal_reply read_only nl_auto_run_fields chat slash reply segments concerns mcp capabilities nl_examples].freeze

      # A tool-level `read_only:` boolean (3.0.1 P13) — declares whether EXECUTING
      # the tool mutates owner data. This is the NL auto-run gate's question
      # (Pito::Chat::Handlers::Unknown#read_only?): a high-confidence NL match may
      # auto-run a tool only when it is read-only in THIS sense. Deliberately
      # distinct from `mcp.read_only` below — that key is the strict MCP
      # readOnlyHint each client sees, where warming a persistent cache or calling
      # an external API counts as an effect (the analytics four declare
      # `mcp.read_only: false` yet mutate no owner data, so they carry
      # `read_only: true` here). When the tool-level key is absent the gate falls
      # back to `mcp.read_only`. The schema-integrity suite pins the EXACT
      # effective auto-runnable set — widening it is a reviewed act.

      # A per-tool `nl_auto_run_fields:` (Q17, 3.8.0) — the FIELD-SCOPED NL
      # auto-run exception: an optional Array of field tokens for which the NL
      # gate may auto-run this WRITE tool's mapped command even though the tool
      # is not read-only (Pito::Chat::Handlers::Unknown#auto_run_field?). Only
      # the SHAPE is validated here (non-blank String tokens); the
      # schema-integrity suite pins the exact declared set — widening it is a
      # reviewed act. See the key's comment on the `update` tool in tools.yml
      # for the safety argument (footage is local-only and reversible).

      # A top-level `nl:` block — the NL mapper's ontology-owned knobs (content
      # is authored separately in tools.yml by the orchestrator; this key only
      # says the SHAPE is legal). Distinct from the per-tool `nl_examples:`
      # above: nl.exemplars are the mapper's say → run few-shot corpus for the
      # WHOLE ontology, nl_examples are per-tool authored phrasings. The router
      # reads thresholds + synonyms; the mapper retrieval-picks exemplars for
      # its few-shot prompt.
      NL_KEYS              = %i[thresholds synonyms exemplars].freeze
      NL_THRESHOLD_KEYS    = %i[auto_run suggest].freeze
      NL_EXEMPLAR_KEYS     = %i[say run].freeze

      # Capability blocks (v1.6 unified grammar) — a per-tool `capabilities:` declares
      # the CONFIG vocabulary that --help, MCP, and autocomplete all read: per-noun
      # `columns` (name → aliases/desc copy keys + sortable/requires_with/
      # internal flags) and `filters` (token or vocabulary + desc). The rendering
      # BEHAVIOR (cell/sort procs, filter scopes) stays in Ruby, keyed by these names;
      # an orphan-guard spec keeps config ↔ Ruby in 1:1 sync.
      CAPABILITY_KEYS       = %i[columns filters].freeze
      CAP_COLUMN_KEYS       = %i[aliases desc sortable requires_with internal default].freeze
      CAP_FILTER_KEYS       = %i[tokens vocabulary scope desc].freeze

      # A per-tool `nl_examples:` — an optional Array of natural-language phrasings
      # a chatting owner might type for this tool. One ontology, three consumers:
      # the NL router embeds these phrasings to route free-text chat; the MCP tool
      # descriptions surface them so a client model knows when to call this tool;
      # and the mapper's few-shot prompt reads them as worked examples. The corpus
      # itself is authored separately in tools.yml — this key only says the SHAPE
      # is legal (non-empty Strings) when a tool declares one.

      # MCP tool blocks — a per-tool `mcp:` promotes a READ-ONLY tool into an
      # MCP tool; the top-level `mcp_readers:` declares tools with no backing tool
      # (pito_conversations / pito_messages). `input:`/`params:` are an INDEPENDENT
      # declaration (NOT derived from chat.slots) — the Executor interpolates params
      # into the `input:` grammar template.
      # `read_only` is REQUIRED on every tool (tool-backed and reader alike): the
      # readOnlyHint annotation each client sees is declared per tool in config,
      # never assumed — a tool whose read path warms a persistent cache or calls
      # an external API (the analytics four) declares `read_only: false`.
      MCP_KEYS             = %i[tool description read_only params input bare_input input_suffixes].freeze
      MCP_REQUIRED         = %i[tool description read_only].freeze
      MCP_READER_KEYS      = %i[tool description read_only params].freeze
      MCP_READER_REQUIRED  = %i[tool description read_only].freeze
      MCP_PARAM_KEYS       = %i[type enum required items hint capability].freeze
      MCP_PARAM_TYPES      = %w[string integer number boolean array].freeze
      # A param may declare `capability: columns|filters|sort` — a REFERENCE to the
      # backing tool's `capabilities:` vocabulary. The Registry derives the param's
      # per-noun enumeration (description) and the Executor derives the allowlist it
      # validates against, both from `Pito::Grammar::Capability` — so the MCP schema
      # can never drift from the chatbox grammar (no hardcoded lists).
      MCP_CAPABILITY_REFS  = %w[columns filters sort].freeze
      AVAILABILITY_KEYS    = %i[chat slash].freeze
      CHAT_KEYS            = %i[slots dispatch segment_of web_flag].freeze
      # A `segment_of:` block marks a chat tool as a "segment tool":
      # a top-level promotion of one parent (show/analyze) segment into its own tool.
      # FLAT form: `{ tool:, segment: }` (the typed noun routes the parent entity).
      SEGMENT_OF_KEYS      = %i[tool segment].freeze
      # KEYED (per-noun) form: `{ <noun>: <branch>, … }` where each
      # branch also FORCES the parent entity and may carry noun `aliases:`.
      SEGMENT_OF_BRANCH_KEYS = %i[tool segment entity aliases].freeze
      SLASH_KEYS           = %i[auth description slots dispatch].freeze
      REPLY_KEYS           = %i[targets].freeze
      SLOT_KEYS            = %i[name kind source optional repeatable introducer when].freeze
      TARGET_KEYS          = %i[mode ref args concern aliases].freeze
      REF_KEYS             = %i[resolver].freeze
      ARG_KEYS             = %i[resolver].freeze
      SEGMENT_KEYS         = %i[builder kind default fill reply_target emit_if aliases].freeze
      SEGMENT_REQUIRED     = %i[builder kind reply_target].freeze
      CONCERNS_KEYS        = %i[pager].freeze
      PAGER_KEYS           = %i[page_size more_tool max_page_size].freeze
      # A `dispatch:` Hash routes a tool either client-side (`{ client: … }`) or
      # through the chat_controller slash path (`{ controller: … }`, no handler class).
      DISPATCH_HASH_KEYS   = %i[client controller].freeze

      # ── Closed value sets (enums) ─────────────────────────────────────────────
      REPLY_MODES   = %w[append mutate].freeze
      SEGMENT_KINDS = %w[system enhanced].freeze
      # Canonical event kind set — derived from Event::KINDS in app/models/event.rb.
      # Validated against the kinds: key in universal_reply entries.
      EVENT_KINDS   = %w[
        echo system error enhanced thinking confirmation
        system_follow_up enhanced_follow_up confirmation_follow_up
        theme_diff ai
      ].freeze
      # enum/literal/kv resolve against a `source:` vocabulary; free slurps free text.
      # (literal = exact-match sentinel — also gates `when:` conditional slots; kv =
      # key=value pairs. Both are the /config provider→keys grammar shape.)
      SLOT_KINDS    = %w[enum free literal kv].freeze
      TOOL_AUTH     = %w[session public].freeze
      BRANCH_AUTH   = %w[any unauthenticated_only authenticated_only].freeze
      ENTITIES      = %w[channel vid game].freeze
      CONCERN_NAMES = %w[pager].freeze

      # ── Allow-lists for constructs whose live registries do not exist yet ──────
      # These closed sets stand in for registries that don't exist yet.
      # Re-point each at its registry (and delete the constant) once it lands.
      #
      # Derived from the live Pito::Dispatch::Predicates registry (named emit_if: guards).
      PREDICATES = Pito::Dispatch::Predicates.names.freeze
      # Derived from the live Pito::Dispatch::Availability registry (named
      # tool-level `enabled_if:` gates — NOT the pre-existing `availability:`
      # Hash above, which is the unrelated chat/slash SURFACE-reachability
      # block; `enabled_if:` is a GLOBAL readiness condition, in the spirit
      # of `auth:` but resolved live instead of by session state).
      AVAILABILITY_CONDITIONS = Pito::Dispatch::Availability.names.freeze
      # Derived from the live Pito::Dispatch::Resolvers registry — the registry
      # is the single source of truth — this constant is a string projection of
      # Resolvers.names for the schema validator.
      RESOLVERS = Pito::Dispatch::Resolvers.names.map(&:to_s).freeze
      # Client-side dispatch kinds (`dispatch: { client: … }`) handled in the browser.
      CLIENT_ACTIONS = %w[theme].freeze
      # Controller-routed dispatch kinds (`dispatch: { controller: … }`): commands
      # with NO handler class, executed by the chat_controller slash routing path
      # (login/logout/connect/new/resume). Declarative today; nothing reads it
      # at runtime yet.
      CONTROLLER_ACTIONS = %w[login logout connect new resume].freeze

      # A single schema violation: a dotted `path` into the document + a `message`.
      Error = Struct.new(:path, :message) do
        def to_s
          "#{path}: #{message}"
        end
      end

      module_function

      # Structural validation of a loaded tools.yml document (symbol-keyed, as
      # Config.data produces). Returns a path-sorted Array<Error>; [] when valid.
      def validate(doc)
        Validator.new(doc).run.errors.sort_by(&:path)
      end

      # Cross-namespace alias uniqueness. Within one dispatch namespace (chat /
      # slash / reply) a token (canonical name OR alias) must map to exactly one
      # tool. universal_reply tools live in the :reply namespace. Returns
      # Array<Error>; [] when there are no collisions.
      def alias_collisions(doc)
        index = { chat: {}, slash: {}, reply: {} }

        (doc[:universal_reply] || {}).each do |vname, vbody|
          record_tokens(index[:reply], vname, vbody[:aliases])
        end

        (doc[:tools] || {}).each do |vname, vbody|
          %i[chat slash reply].each do |ns|
            record_tokens(index[ns], vname, vbody[:aliases]) if vbody.is_a?(Hash) && vbody.key?(ns)
          end
        end

        index.flat_map do |ns, tokens|
          tokens.filter_map do |token, tools|
            next if tools.uniq.size <= 1

            Error.new("#{ns}:#{token}", "token maps to multiple tools #{tools.uniq.sort.inspect}")
          end
        end
      end

      # Closest allowed key to +key+ (Levenshtein ≤ 2), or nil. Ties broken
      # alphabetically for determinism. Exposed for the schema unit spec.
      def suggest(key, allowed)
        candidate = allowed
          .map { |a| [ Pito::Fuzzy.levenshtein(key.to_s, a.to_s), a.to_s ] }
          .min_by { |distance, name| [ distance, name ] }
        return nil unless candidate

        distance, name = candidate
        distance.positive? && distance <= 2 ? name : nil
      end

      def record_tokens(index, vname, aliases)
        ([ vname ] + Array(aliases)).each do |token|
          (index[token.to_s.downcase] ||= []) << vname.to_s
        end
      end

      # ── The recursive structural walker ────────────────────────────────────────
      #
      # Accumulates Errors as it descends; every method threads a dotted `path`
      # string so each violation points at the exact location in the document.
      class Validator
        attr_reader :errors

        def initialize(doc)
          @doc    = doc
          @errors = []
        end

        def run
          return self unless expect_hash(@doc, "(root)")

          check_keys(@doc, Schema::TOP_KEYS, "", required: %i[schema_version tools])
          validate_schema_version(@doc[:schema_version])
          validate_universal_reply(@doc[:universal_reply]) if @doc.key?(:universal_reply)
          validate_vocabularies(@doc[:vocabularies]) if @doc.key?(:vocabularies)
          validate_tools(@doc[:tools]) if @doc.key?(:tools)
          validate_mcp_readers(@doc[:mcp_readers]) if @doc.key?(:mcp_readers)
          validate_nl(@doc[:nl]) if @doc.key?(:nl)
          self
        end

        private

        # ── top-level sections ──────────────────────────────────────────────────

        def validate_schema_version(version)
          err("schema_version", "expected an Integer, got #{version.class}") unless version.is_a?(Integer)
        end

        def validate_universal_reply(section)
          return unless expect_hash(section, "universal_reply")

          section.each do |vname, vbody|
            path = join("universal_reply", vname)
            next unless expect_hash(vbody, path)

            check_keys(vbody, Schema::UNIVERSAL_KEYS, path, required: %i[mode])
            validate_enum(vbody[:mode], Schema::REPLY_MODES, join(path, "mode"), "mode") if vbody.key?(:mode)
            validate_aliases(vbody[:aliases], path) if vbody.key?(:aliases)
            validate_universal_kinds(vbody[:kinds], join(path, "kinds")) if vbody.key?(:kinds)
            validate_universal_except(vbody[:except], join(path, "except")) if vbody.key?(:except)
          end
        end

        def validate_universal_kinds(kinds, path)
          return err(path, "expected an Array, got #{kinds.class}") unless kinds.is_a?(Array)

          kinds.each_with_index do |kind, i|
            validate_membership(kind.to_s, Schema::EVENT_KINDS, "#{path}[#{i}]", "event kind")
          end
        end

        def validate_universal_except(except_list, path)
          return err(path, "expected an Array, got #{except_list.class}") unless except_list.is_a?(Array)

          targets = all_reply_targets
          except_list.each_with_index do |target, i|
            validate_membership(target.to_s, targets, "#{path}[#{i}]", "reply target")
          end
        end

        # Collect all reply_target ids declared in the document (used to validate except: entries).
        def all_reply_targets
          @all_reply_targets ||= (@doc[:tools] || {}).flat_map do |_, vbody|
            next [] unless vbody.is_a?(Hash)

            (vbody.dig(:reply, :targets) || {}).keys.map(&:to_s)
          end.uniq
        end

        def validate_vocabularies(section)
          return unless expect_hash(section, "vocabularies")

          section.each do |name, body|
            path = join("vocabularies", name)
            next unless expect_hash(body, path)

            check_keys(body, Schema::VOCAB_KEYS, path)
          end
        end

        def validate_tools(section)
          return unless expect_hash(section, "tools")

          section.each { |name, body| validate_tool(name, body) }
        end

        # ── one tool ────────────────────────────────────────────────────────────

        def validate_tool(name, body)
          path = join("tools", name)
          return unless expect_hash(body, path)

          check_keys(body, Schema::TOOL_KEYS, path)
          if (body.keys & %i[chat slash reply]).empty?
            err(path, "tool declares no branch (expected one of chat/slash/reply)")
          end

          validate_aliases(body[:aliases], path) if body.key?(:aliases)
          validate_string(body[:description], join(path, "description")) if body.key?(:description)
          validate_availability(body[:availability], join(path, "availability")) if body.key?(:availability)
          validate_tool_condition(body[:enabled_if], join(path, "enabled_if")) if body.key?(:enabled_if)
          validate_enum(body[:auth], Schema::TOOL_AUTH, join(path, "auth"), "auth") if body.key?(:auth)
          validate_boolean(body[:internal], join(path, "internal")) if body.key?(:internal)
          validate_boolean(body[:universal_reply], join(path, "universal_reply")) if body.key?(:universal_reply)
          validate_boolean(body[:read_only], join(path, "read_only")) if body.key?(:read_only)
          validate_nl_auto_run_fields(body[:nl_auto_run_fields], join(path, "nl_auto_run_fields")) if body.key?(:nl_auto_run_fields)
          validate_chat(body[:chat], join(path, "chat")) if body.key?(:chat)
          validate_slash(body[:slash], join(path, "slash")) if body.key?(:slash)
          validate_reply(body[:reply], join(path, "reply")) if body.key?(:reply)
          validate_segments(body[:segments], join(path, "segments")) if body.key?(:segments)
          validate_concerns(body[:concerns], join(path, "concerns")) if body.key?(:concerns)
          validate_mcp(body[:mcp], join(path, "mcp")) if body.key?(:mcp)
          validate_capabilities(body[:capabilities], join(path, "capabilities")) if body.key?(:capabilities)
          validate_nl_examples(body[:nl_examples], join(path, "nl_examples")) if body.key?(:nl_examples)
        end

        # ── Capability blocks (v1.6) ────────────────────────────────────────────
        def validate_capabilities(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::CAPABILITY_KEYS, path)
          validate_cap_columns(body[:columns], join(path, "columns")) if body.key?(:columns)
          validate_cap_filters(body[:filters], join(path, "filters")) if body.key?(:filters)
        end

        # columns: { <noun>: { <col-name>: { aliases, desc, sortable, requires_with, internal, default } } }
        def validate_cap_columns(columns, path)
          return unless expect_hash(columns, path)

          columns.each do |noun, cols|
            np = join(path, noun)
            next unless expect_hash(cols, np)

            cols.each do |name, spec|
              cp = join(np, name)
              next unless expect_hash(spec, cp)

              check_keys(spec, Schema::CAP_COLUMN_KEYS, cp)
              validate_aliases(spec[:aliases], join(cp, "aliases")) if spec.key?(:aliases)
              validate_string(spec[:desc], join(cp, "desc")) if spec.key?(:desc)
              %i[sortable requires_with internal default].each do |flag|
                validate_boolean(spec[flag], join(cp, flag.to_s)) if spec.key?(flag)
              end
            end
          end
        end

        # filters: { <noun>: { <filter>: { tokens:[…] | vocabulary:, scope:, desc: } } }
        def validate_cap_filters(filters, path)
          return unless expect_hash(filters, path)

          filters.each do |noun, defs|
            np = join(path, noun)
            next unless expect_hash(defs, np)

            defs.each do |name, spec|
              fp = join(np, name)
              next unless expect_hash(spec, fp)

              check_keys(spec, Schema::CAP_FILTER_KEYS, fp)
              validate_aliases(spec[:tokens], join(fp, "tokens")) if spec.key?(:tokens)
              validate_string(spec[:vocabulary], join(fp, "vocabulary")) if spec.key?(:vocabulary)
              validate_string(spec[:scope], join(fp, "scope")) if spec.key?(:scope)
              validate_string(spec[:desc], join(fp, "desc")) if spec.key?(:desc)
              validate_cap_filter_matcher(spec, fp)
            end
          end
        end

        # A filter with neither a non-empty tokens list nor a vocabulary can never
        # match input — it is structurally valid but wholly inert (a blank help
        # row). Require one or the other.
        def validate_cap_filter_matcher(spec, path)
          has_tokens     = spec[:tokens].is_a?(Array) && !spec[:tokens].empty?
          has_vocabulary = spec[:vocabulary].is_a?(String) && !spec[:vocabulary].empty?
          return if has_tokens || has_vocabulary

          err(path, "filter must declare tokens (non-empty Array) or vocabulary (String)")
        end

        # ── NL examples ───────────────────────────────────────────────────────────
        # An optional Array of non-empty phrasing Strings (see the nl_examples
        # comment at the constant definition for why three consumers read this).
        def validate_nl_examples(examples, path)
          return err(path, "expected an Array, got #{examples.class}") unless examples.is_a?(Array)

          examples.each_with_index do |example, i|
            ex_path = "#{path}[#{i}]"
            if !example.is_a?(String)
              err(ex_path, "expected a String, got #{example.class}")
            elsif example.strip.empty?
              err(ex_path, "nl_examples entries must not be blank")
            end
          end
        end

        # ── NL auto-run field exception (per-tool `nl_auto_run_fields:`) ─────────
        # A non-empty Array of non-blank field-token Strings (see the
        # NL_AUTO_RUN-adjacent comment at the TOOL_KEYS constants for the WHY;
        # the schema-integrity suite pins the exact declared set). An EMPTY
        # array is rejected: a declared-but-empty exception can never match a
        # field, so it is wholly inert — demand the key be absent instead.
        def validate_nl_auto_run_fields(fields, path)
          return err(path, "expected an Array, got #{fields.class}") unless fields.is_a?(Array)
          return err(path, "must not be empty (omit the key instead)") if fields.empty?

          fields.each_with_index do |field, i|
            f_path = "#{path}[#{i}]"
            if !field.is_a?(String)
              err(f_path, "expected a String, got #{field.class}")
            elsif field.strip.empty?
              err(f_path, "nl_auto_run_fields entries must not be blank")
            end
          end
        end

        # ── NL ontology (top-level `nl:` block) ──────────────────────────────────
        # See the NL_KEYS comment at the constant definition for the shape + why
        # this is distinct from per-tool nl_examples above.
        def validate_nl(section)
          return unless expect_hash(section, "nl")

          check_keys(section, Schema::NL_KEYS, "nl")
          validate_nl_thresholds(section[:thresholds], "nl.thresholds") if section.key?(:thresholds)
          validate_nl_synonyms(section[:synonyms], "nl.synonyms") if section.key?(:synonyms)
          validate_nl_exemplars(section[:exemplars], "nl.exemplars") if section.key?(:exemplars)
        end

        # thresholds: { auto_run:, suggest: } — both Numeric 0..1; auto_run must
        # be >= suggest when both are present (a lower auto-run bar than the
        # suggest bar would let the router fire before ever surfacing a suggestion).
        def validate_nl_thresholds(thresholds, path)
          return unless expect_hash(thresholds, path)

          check_keys(thresholds, Schema::NL_THRESHOLD_KEYS, path)
          Schema::NL_THRESHOLD_KEYS.each do |key|
            validate_unit_float(thresholds[key], join(path, key.to_s)) if thresholds.key?(key)
          end

          auto_run, suggest = thresholds[:auto_run], thresholds[:suggest]
          return unless auto_run.is_a?(Numeric) && suggest.is_a?(Numeric)

          err(path, "auto_run (#{auto_run}) must be >= suggest (#{suggest})") if auto_run < suggest
        end

        # synonyms: { <word> => <canonical> } — a non-blank String key (a Symbol
        # after Config's symbolize_names load) + a non-empty String value; the
        # NL router folds the key token into the value before matching.
        def validate_nl_synonyms(synonyms, path)
          return err(path, "expected a Hash, got #{synonyms.class}") unless synonyms.is_a?(Hash)

          synonyms.each do |from, to|
            pair_path = join(path, from)
            if from.is_a?(String) || from.is_a?(Symbol)
              err(pair_path, "synonym key must not be blank") if from.to_s.strip.empty?
            else
              # YAML happily parses `5: vids` — an Integer key stringifies
              # non-blank, so without this check it sailed through untyped.
              err(pair_path, "expected a String key, got #{from.class}")
            end
            if to.is_a?(String)
              err(pair_path, "synonym value must not be blank") if to.strip.empty?
            else
              err(pair_path, "expected a String value, got #{to.class}")
            end
          end
        end

        # exemplars: [ { say:, run: }, … ] — the mapper's say → run few-shot
        # corpus for the whole ontology; both keys required, both non-empty Strings.
        def validate_nl_exemplars(exemplars, path)
          return err(path, "expected an Array, got #{exemplars.class}") unless exemplars.is_a?(Array)

          exemplars.each_with_index do |exemplar, i|
            ex_path = "#{path}[#{i}]"
            next unless expect_hash(exemplar, ex_path)

            check_keys(exemplar, Schema::NL_EXEMPLAR_KEYS, ex_path, required: Schema::NL_EXEMPLAR_KEYS)
            validate_nonblank_string(exemplar[:say], join(ex_path, "say")) if exemplar.key?(:say)
            validate_nonblank_string(exemplar[:run], join(ex_path, "run")) if exemplar.key?(:run)
          end
        end

        # ── MCP tool blocks ──────────────────────────────────────────────────────
        # A per-tool `mcp:` block; `params`/`input`/`input_suffixes` are optional
        # (a param-less tool is valid). Keys/types are validated; the read-only
        # allowlist + tool-name uniqueness + placeholder⊆params live in the
        # schema-integrity SUITE (they need the whole document, not one node).
        def validate_mcp(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::MCP_KEYS, path, required: Schema::MCP_REQUIRED)
          validate_string(body[:tool], join(path, "tool")) if body.key?(:tool)
          validate_string(body[:description], join(path, "description")) if body.key?(:description)
          validate_boolean(body[:read_only], join(path, "read_only")) if body.key?(:read_only)
          validate_string(body[:input], join(path, "input")) if body.key?(:input)
          validate_mcp_params(body[:params], join(path, "params")) if body.key?(:params)
          validate_mcp_input_suffixes(body[:input_suffixes], join(path, "input_suffixes")) if body.key?(:input_suffixes)
        end

        def validate_mcp_params(params, path)
          return unless expect_hash(params, path)

          params.each do |name, spec|
            p = join(path, name)
            next unless expect_hash(spec, p)

            check_keys(spec, Schema::MCP_PARAM_KEYS, p, required: %i[type])
            validate_enum(spec[:type], Schema::MCP_PARAM_TYPES, join(p, "type"), "mcp param type") if spec.key?(:type)
            validate_boolean(spec[:required], join(p, "required")) if spec.key?(:required)
            validate_string(spec[:hint], join(p, "hint")) if spec.key?(:hint)
            validate_string(spec[:items], join(p, "items")) if spec.key?(:items)
            validate_mcp_enum(spec[:enum], join(p, "enum")) if spec.key?(:enum)
            validate_enum(spec[:capability], Schema::MCP_CAPABILITY_REFS, join(p, "capability"), "mcp param capability") if spec.key?(:capability)
          end
        end

        # An mcp param `enum:` is an Array of allowed scalar values.
        def validate_mcp_enum(values, path)
          return err(path, "expected an Array, got #{values.class}") unless values.is_a?(Array)

          values.each_with_index do |v, i|
            err("#{path}[#{i}]", "expected a scalar, got #{v.class}") unless scalar?(v)
          end
        end

        def validate_mcp_input_suffixes(suffixes, path)
          return unless expect_hash(suffixes, path)

          suffixes.each { |name, tmpl| validate_string(tmpl, join(path, name)) }
        end

        # Top-level `mcp_readers:` — reader tools with no backing tool.
        def validate_mcp_readers(section)
          return unless expect_hash(section, "mcp_readers")

          section.each do |name, body|
            path = join("mcp_readers", name)
            next unless expect_hash(body, path)

            check_keys(body, Schema::MCP_READER_KEYS, path, required: Schema::MCP_READER_REQUIRED)
            validate_string(body[:tool], join(path, "tool")) if body.key?(:tool)
            validate_string(body[:description], join(path, "description")) if body.key?(:description)
            validate_boolean(body[:read_only], join(path, "read_only")) if body.key?(:read_only)
            validate_mcp_params(body[:params], join(path, "params")) if body.key?(:params)
          end
        end

        def validate_availability(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::AVAILABILITY_KEYS, path)
          Schema::AVAILABILITY_KEYS.each do |key|
            validate_boolean(body[key], join(path, key)) if body.key?(key)
          end
        end

        # ── branches ──────────────────────────────────────────────────────────────

        def validate_chat(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::CHAT_KEYS, path)
          validate_slots(body[:slots], join(path, "slots")) if body.key?(:slots)
          validate_dispatch(body[:dispatch], join(path, "dispatch")) if body.key?(:dispatch)
          validate_segment_of(body[:segment_of], join(path, "segment_of")) if body.key?(:segment_of)
        end

        # A `segment_of:` block binds a segment tool to its parent segment(s). Two
        # shapes are accepted:
        #
        #   FLAT   `{ tool:, segment: }`  — one pair; the typed noun routes the
        #                                   entity in the parent.
        #   KEYED  `{ <noun>: { tool:, segment:, entity:[, aliases:] }, … }` — the
        #                                   `linked` two-word forms: the noun names
        #                                   the segment and `entity:` FORCES the
        #                                   parent's branch (the id is the OTHER
        #                                   entity's), so each segment is validated
        #                                   against that forced entity specifically.
        #
        # Either way the parent tool must exist AND declare a segments block, and
        # the segment name must appear in that parent's table (a typo names its
        # exact path). Detection: the block itself carries the pair (flat) or its
        # keys are nouns (keyed).
        def validate_segment_of(body, path)
          return unless expect_hash(body, path)

          if body.key?(:tool) || body.key?(:segment)
            validate_segment_of_flat(body, path)
          else
            validate_segment_of_keyed(body, path)
          end
        end

        # FLAT form — the noun routes the entity in the parent (any-entity segment).
        def validate_segment_of_flat(body, path)
          check_keys(body, Schema::SEGMENT_OF_KEYS, path, required: %i[tool segment])
          validate_string(body[:tool], join(path, "tool")) if body.key?(:tool)
          validate_string(body[:segment], join(path, "segment")) if body.key?(:segment)
          validate_segment_binding(body, path)
        end

        # KEYED form — one branch per noun; `entity:` FORCES (and scopes) the segment.
        def validate_segment_of_keyed(body, path)
          body.each do |noun, branch|
            bpath = join(path, noun)
            next unless expect_hash(branch, bpath)

            check_keys(branch, Schema::SEGMENT_OF_BRANCH_KEYS, bpath, required: %i[tool segment entity])
            validate_string(branch[:tool], join(bpath, "tool")) if branch.key?(:tool)
            validate_string(branch[:segment], join(bpath, "segment")) if branch.key?(:segment)
            validate_enum(branch[:entity], Schema::ENTITIES, join(bpath, "entity"), "entity") if branch.key?(:entity)
            validate_aliases(branch[:aliases], bpath) if branch.key?(:aliases)
            validate_segment_binding(branch, bpath, entity: branch[:entity])
          end
        end

        # Shared cross-validation: parent tool exists + declares a segments block,
        # and `segment` is a segment of that parent — scoped to `entity` when given.
        def validate_segment_binding(body, path, entity: nil)
          return unless body[:tool].is_a?(String) && body[:segment].is_a?(String)

          parent_cfg = @doc.dig(:tools, body[:tool].to_sym)
          unless parent_cfg.is_a?(Hash) && parent_cfg[:segments].is_a?(Hash)
            return err(join(path, "tool"),
                       "segment_of.tool #{body[:tool].inspect} is not a tool declaring a segments block")
          end

          segs  = parent_cfg[:segments]
          scoped = entity.is_a?(String) && segs[entity.to_sym].is_a?(Hash)
          known =
            if scoped
              segs[entity.to_sym].keys.map(&:to_s)
            else
              segs.values.flat_map { |s| s.is_a?(Hash) ? s.keys.map(&:to_s) : [] }.uniq
            end
          return if known.include?(body[:segment])

          scope = scoped ? " for #{entity}" : ""
          err(join(path, "segment"),
              "segment_of.segment #{body[:segment].inspect} is not a segment of #{body[:tool]}#{scope} " \
              "(known: #{known.sort.join(', ')})")
        end

        def validate_slash(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::SLASH_KEYS, path)
          validate_enum(body[:auth], Schema::BRANCH_AUTH, join(path, "auth"), "auth") if body.key?(:auth)
          validate_string(body[:description], join(path, "description")) if body.key?(:description)
          validate_slots(body[:slots], join(path, "slots")) if body.key?(:slots)
          validate_dispatch(body[:dispatch], join(path, "dispatch")) if body.key?(:dispatch)
        end

        def validate_reply(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::REPLY_KEYS, path)
          validate_targets(body[:targets], join(path, "targets")) if body.key?(:targets)
        end

        # ── slots ─────────────────────────────────────────────────────────────────

        def validate_slots(slots, path)
          return err(path, "expected an Array, got #{slots.class}") unless slots.is_a?(Array)

          slots.each_with_index { |slot, i| validate_slot(slot, "#{path}[#{i}]") }
        end

        def validate_slot(slot, path)
          return unless expect_hash(slot, path)

          check_keys(slot, Schema::SLOT_KEYS, path, required: %i[name kind])
          validate_string(slot[:name], join(path, "name")) if slot.key?(:name)
          validate_slot_kind(slot, path) if slot.key?(:kind)
          validate_string(slot[:source], join(path, "source")) if slot.key?(:source)
          validate_boolean(slot[:optional], join(path, "optional")) if slot.key?(:optional)
          validate_boolean(slot[:repeatable], join(path, "repeatable")) if slot.key?(:repeatable)
          validate_string(slot[:introducer], join(path, "introducer")) if slot.key?(:introducer)
          validate_when(slot[:when], join(path, "when")) if slot.key?(:when)
        end

        def validate_slot_kind(slot, path)
          validate_enum(slot[:kind], Schema::SLOT_KINDS, join(path, "kind"), "slot kind")
          case slot[:kind]
          when "enum", "literal", "kv"
            err(join(path, "source"), "missing required key (#{slot[:kind]} slots need a source vocabulary)") unless slot.key?(:source)
          when "free"
            err(join(path, "source"), "free slots must not declare a source") if slot.key?(:source)
          end
        end

        # A `when:` conditional gates a slot on an already-resolved prior slot's
        # value — a Hash of { prior_slot_name => [allowed scalar values] } (the
        # /config provider→keys pattern). Shape-only: it does not cross-check that
        # the named prior slot exists (that is a runtime/grammar concern).
        def validate_when(clause, path)
          return unless expect_hash(clause, path)

          clause.each do |slot_name, allowed|
            cond_path = join(path, slot_name)
            unless allowed.is_a?(Array)
              err(cond_path, "expected an Array of allowed values, got #{allowed.class}")
              next
            end
            allowed.each_with_index do |value, i|
              err("#{cond_path}[#{i}]", "condition value must be a scalar, got #{value.class}") unless scalar?(value)
            end
          end
        end

        # ── reply targets ───────────────────────────────────────────────────────

        def validate_targets(targets, path)
          return unless expect_hash(targets, path)

          targets.each { |name, body| validate_target(name, body, join(path, name)) }
        end

        def validate_target(_name, body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::TARGET_KEYS, path, required: %i[mode])
          validate_enum(body[:mode], Schema::REPLY_MODES, join(path, "mode"), "mode") if body.key?(:mode)
          validate_ref(body[:ref], join(path, "ref")) if body.key?(:ref)
          validate_args(body[:args], join(path, "args")) if body.key?(:args)
          validate_enum(body[:concern], Schema::CONCERN_NAMES, join(path, "concern"), "concern") if body.key?(:concern)
          validate_aliases(body[:aliases], path) if body.key?(:aliases)
        end

        def validate_ref(ref, path)
          return unless expect_hash(ref, path)

          check_keys(ref, Schema::REF_KEYS, path, required: %i[resolver])
          validate_resolver(ref[:resolver], join(path, "resolver")) if ref.key?(:resolver)
        end

        def validate_args(args, path)
          return unless expect_hash(args, path)

          args.each do |name, spec|
            arg_path = join(path, name)
            next unless expect_hash(spec, arg_path)

            check_keys(spec, Schema::ARG_KEYS, arg_path, required: %i[resolver])
            validate_resolver(spec[:resolver], join(arg_path, "resolver")) if spec.key?(:resolver)
          end
        end

        # ── segments ────────────────────────────────────────────────────────────

        def validate_segments(segments, path)
          return unless expect_hash(segments, path)

          segments.each do |entity, segs|
            entity_path = join(path, entity)
            validate_membership(entity, Schema::ENTITIES, entity_path, "entity")
            next unless expect_hash(segs, entity_path)

            segs.each { |name, body| validate_segment(body, join(entity_path, name)) }
            validate_segment_alias_uniqueness(segs, entity_path)
          end
        end

        # Checks that no token (segment name or alias) appears more than once
        # within the same tool+entity block.
        def validate_segment_alias_uniqueness(segs, entity_path)
          seen = {}   # token_string → first segment name that claimed it
          segs.each do |seg_name, body|
            name_str = seg_name.to_s
            if seen.key?(name_str)
              err(join(entity_path, name_str),
                  "segment name #{name_str.inspect} collides with #{seen[name_str].inspect}")
            else
              seen[name_str] = name_str
            end

            next unless body.is_a?(Hash) && body[:aliases].is_a?(Array)

            body[:aliases].each_with_index do |token, i|
              # Booleans and non-scalars are already caught by validate_aliases — skip them here.
              next unless scalar?(token) && token != true && token != false

              alias_str  = token.to_s
              alias_path = "#{join(entity_path, name_str)}.aliases[#{i}]"
              if seen.key?(alias_str)
                err(alias_path,
                    "alias #{alias_str.inspect} collides with segment #{seen[alias_str].inspect}")
              else
                seen[alias_str] = name_str
              end
            end
          end
        end

        def validate_segment(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::SEGMENT_KEYS, path, required: Schema::SEGMENT_REQUIRED)
          validate_string(body[:builder], join(path, "builder")) if body.key?(:builder)
          validate_enum(body[:kind], Schema::SEGMENT_KINDS, join(path, "kind"), "segment kind") if body.key?(:kind)
          validate_boolean(body[:default], join(path, "default")) if body.key?(:default)
          validate_string(body[:reply_target], join(path, "reply_target")) if body.key?(:reply_target)
          validate_string(body[:fill], join(path, "fill")) if present?(body, :fill)
          validate_predicate(body[:emit_if], join(path, "emit_if")) if present?(body, :emit_if)
          validate_aliases(body[:aliases], path) if body.key?(:aliases)
        end

        # ── concerns ────────────────────────────────────────────────────────────

        def validate_concerns(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::CONCERNS_KEYS, path)
          validate_pager(body[:pager], join(path, "pager")) if body.key?(:pager)
        end

        def validate_pager(body, path)
          return unless expect_hash(body, path)

          check_keys(body, Schema::PAGER_KEYS, path)
          validate_integer(body[:page_size], join(path, "page_size")) if body.key?(:page_size)
          validate_string(body[:more_tool], join(path, "more_tool")) if body.key?(:more_tool)
          validate_integer(body[:max_page_size], join(path, "max_page_size")) if body.key?(:max_page_size)
        end

        # ── leaf validators ───────────────────────────────────────────────────────

        def validate_dispatch(dispatch, path)
          case dispatch
          when String
            err(path, "dispatch class must not be blank") if dispatch.strip.empty?
          when Hash
            check_keys(dispatch, Schema::DISPATCH_HASH_KEYS, path)
            unless dispatch.key?(:client) || dispatch.key?(:controller)
              err(path, "dispatch hash must declare a client or controller action")
            end
            validate_enum(dispatch[:client], Schema::CLIENT_ACTIONS, join(path, "client"), "client action") if dispatch.key?(:client)
            validate_enum(dispatch[:controller], Schema::CONTROLLER_ACTIONS, join(path, "controller"), "controller action") if dispatch.key?(:controller)
          else
            err(path, "expected a class String, { client: … }, or { controller: … } Hash, got #{dispatch.class}")
          end
        end

        def validate_aliases(aliases, path)
          alias_path = join(path, "aliases")
          return err(alias_path, "expected an Array of tokens, got #{aliases.class}") unless aliases.is_a?(Array)

          aliases.each_with_index do |token, i|
            if token == true || token == false
              # YAML 1.1 coerces bare on/off/yes/no to booleans — the
              # author meant a word token; demand quoting instead of guessing.
              err("#{alias_path}[#{i}]", "boolean #{token} — quote YAML-boolean tokens (\"on\"/\"off\"/\"yes\"/\"no\")")
            elsif !scalar?(token)
              err("#{alias_path}[#{i}]", "alias token must be a scalar, got #{token.class}")
            end
          end
        end

        def validate_resolver(name, path)
          return err(path, "expected a resolver name String, got #{name.class}") unless name.is_a?(String)

          validate_membership(name, Schema::RESOLVERS, path, "resolver")
        end

        def validate_predicate(name, path)
          return err(path, "expected a predicate name String, got #{name.class}") unless name.is_a?(String)

          validate_membership(name, Schema::PREDICATES, path, "predicate")
        end

        def validate_tool_condition(name, path)
          return err(path, "expected a condition name String, got #{name.class}") unless name.is_a?(String)

          validate_membership(name, Schema::AVAILABILITY_CONDITIONS, path, "condition")
        end

        def validate_membership(value, allowed, path, label)
          return if allowed.include?(value.to_s)

          hint = Schema.suggest(value, allowed)
          err(path, "unknown #{label} #{value.inspect}#{did_you_mean(hint)} (allowed: #{allowed.join(', ')})")
        end

        def validate_enum(value, allowed, path, label)
          return if allowed.include?(value)

          hint = scalar?(value) ? Schema.suggest(value, allowed) : nil
          err(path, "invalid #{label} #{value.inspect}#{did_you_mean(hint)} (allowed: #{allowed.join(', ')})")
        end

        def validate_string(value, path)
          err(path, "expected a String, got #{value.class}") unless value.is_a?(String)
        end

        def validate_boolean(value, path)
          err(path, "expected true/false, got #{value.class}") unless [ true, false ].include?(value)
        end

        def validate_integer(value, path)
          err(path, "expected an Integer, got #{value.class}") unless value.is_a?(Integer)
        end

        def validate_unit_float(value, path)
          return err(path, "expected a Numeric 0..1, got #{value.class}") unless value.is_a?(Numeric)

          err(path, "expected a Numeric 0..1, got #{value.inspect}") unless (0..1).cover?(value)
        end

        def validate_nonblank_string(value, path)
          return err(path, "expected a String, got #{value.class}") unless value.is_a?(String)

          err(path, "must not be blank") if value.strip.empty?
        end

        # ── shared helpers ────────────────────────────────────────────────────────

        # Reject unknown keys (with a did-you-mean hint) + report missing required.
        def check_keys(hash, allowed, path, required: [])
          hash.each_key do |key|
            next if allowed.include?(key)

            hint = Schema.suggest(key, allowed)
            err(join(path, key), "unknown key#{did_you_mean(hint)}")
          end
          required.each { |key| err(join(path, key), "missing required key") unless hash.key?(key) }
        end

        def expect_hash(value, path)
          return true if value.is_a?(Hash)

          err(path, "expected a Hash, got #{value.class}")
          false
        end

        def present?(hash, key)
          hash.key?(key) && !hash[key].nil?
        end

        def scalar?(value)
          !(value.is_a?(Hash) || value.is_a?(Array) || value.nil?)
        end

        def did_you_mean(hint)
          hint ? " (did you mean #{hint}?)" : ""
        end

        def err(path, message)
          @errors << Schema::Error.new(path.to_s, message)
        end

        def join(parent, key)
          parent.to_s.empty? ? key.to_s : "#{parent}.#{key}"
        end
      end
    end
  end
end
