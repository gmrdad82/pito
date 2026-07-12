# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Dispatch::Schema itself — the validator logic, exercised
# with synthetic documents so its error reporting is pinned independently of the
# real tools.yml (which the integrity suite covers). This is the contract the
# schema-integrity suite leans on: a mistyped key, a bad enum, or a colliding
# alias must produce a precise, path-named Error.
RSpec.describe Pito::Dispatch::Schema, type: :dispatch do
  # Smallest well-formed document: one verb with one (empty) branch.
  def valid_doc
    { schema_version: 1, tools: { greet: { chat: { slots: [] } } } }
  end

  def messages(doc)
    described_class.validate(doc).map(&:to_s)
  end

  describe ".validate — happy path" do
    it "returns no errors for a minimal well-formed document" do
      expect(described_class.validate(valid_doc)).to eq([])
    end

    it "accepts a fully-featured verb (branches, segments, concerns, reply)" do
      doc = valid_doc
      doc[:tools][:show] = {
        description: "pito.grammar.chat.show",
        auth:        "session",
        chat:        { slots: [ { name: "id", kind: "free", optional: true } ] },
        segments:    {
          game: {
            "detail" => { builder: "MessageBuilder::Game::Detail", kind: "system", default: true,
                          fill: nil, reply_target: "game_detail", emit_if: nil },
            "linked-videos" => { builder: "MessageBuilder::Game::LinkedVideos", kind: "enhanced",
                                 default: false, fill: nil, reply_target: "game_linked_videos",
                                 emit_if: "has_linked_videos" }
          }
        },
        concerns:    { pager: { page_size: 50, more_tool: "next" } },
        reply:       { targets: { game_list: { mode: "append", ref: { resolver: "id_among_rows" } } } }
      }
      expect(described_class.validate(doc)).to eq([])
    end
  end

  describe ".validate — unknown keys (with did-you-mean)" do
    it "rejects a near-miss target key and suggests the intended one" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_list: { mode: "append", mod: "x" } } } }
      expect(messages(doc)).to include("tools.show.reply.targets.game_list.mod: unknown key (did you mean mode?)")
    end

    it "rejects an unknown top-level key" do
      doc = valid_doc.merge(toolz: {})
      expect(messages(doc)).to include("toolz: unknown key (did you mean tools?)")
    end

    it "rejects an unknown key with no near match (no suggestion)" do
      doc = valid_doc
      doc[:tools][:greet][:zzzzzzz] = true
      expect(messages(doc)).to include("tools.greet.zzzzzzz: unknown key")
    end

    it "names an array index in the path for slot violations" do
      doc = valid_doc
      doc[:tools][:greet][:chat][:slots] = [ { name: "x", kind: "free", bogus: 1 } ]
      expect(messages(doc)).to include("tools.greet.chat.slots[0].bogus: unknown key")
    end
  end

  describe ".validate — missing required keys" do
    it "flags a reply target missing its mode" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_list: { ref: { resolver: "id_among_rows" } } } } }
      expect(messages(doc)).to include("tools.show.reply.targets.game_list.mode: missing required key")
    end

    it "flags a slot missing its kind" do
      doc = valid_doc
      doc[:tools][:greet][:chat][:slots] = [ { name: "x" } ]
      expect(messages(doc)).to include("tools.greet.chat.slots[0].kind: missing required key")
    end
  end

  describe ".validate — enums and types" do
    it "rejects an invalid reply mode and lists the allowed set" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_list: { mode: "replace" } } } }
      expect(messages(doc)).to include(
        "tools.show.reply.targets.game_list.mode: invalid mode \"replace\" (allowed: append, mutate)"
      )
    end

    it "rejects an invalid slot kind" do
      doc = valid_doc
      doc[:tools][:greet][:chat][:slots] = [ { name: "x", kind: "sparkle" } ]
      expect(messages(doc)).to include(
        "tools.greet.chat.slots[0].kind: invalid slot kind \"sparkle\" (allowed: enum, free, literal, kv)"
      )
    end

    it "requires an enum slot to declare a source" do
      doc = valid_doc
      doc[:tools][:greet][:chat][:slots] = [ { name: "x", kind: "enum" } ]
      expect(messages(doc)).to include(
        "tools.greet.chat.slots[0].source: missing required key (enum slots need a source vocabulary)"
      )
    end

    it "forbids a free slot from declaring a source" do
      doc = valid_doc
      doc[:tools][:greet][:chat][:slots] = [ { name: "x", kind: "free", source: "nouns" } ]
      expect(messages(doc)).to include("tools.greet.chat.slots[0].source: free slots must not declare a source")
    end

    it "rejects a segment kind outside system/enhanced" do
      doc = valid_doc
      doc[:tools][:show] = { segments: { game: { "detail" => { builder: "B", kind: "loud", reply_target: "game_detail" } } } }
      expect(messages(doc)).to include(
        "tools.show.segments.game.detail.kind: invalid segment kind \"loud\" (allowed: system, enhanced)"
      )
    end

    it "reports a type mismatch for a non-string description" do
      doc = valid_doc
      doc[:tools][:greet][:description] = 42
      expect(messages(doc)).to include("tools.greet.description: expected a String, got Integer")
    end
  end

  describe ".validate — T8.9 slash slot constructs (literal / kv / when:)" do
    # Build a verb whose slash branch carries one slot, minimally well-formed.
    def slash_slot_doc(slot)
      doc = valid_doc
      doc[:tools][:cfg] = { slash: { slots: [ slot ] } }
      doc
    end

    it "accepts a literal slot with a source vocabulary" do
      doc = slash_slot_doc({ name: "provider", kind: "literal", source: "config_providers" })
      expect(described_class.validate(doc)).to eq([])
    end

    it "requires a literal slot to declare a source" do
      doc = slash_slot_doc({ name: "provider", kind: "literal" })
      expect(messages(doc)).to include(
        "tools.cfg.slash.slots[0].source: missing required key (literal slots need a source vocabulary)"
      )
    end

    it "accepts a repeatable kv slot with a source vocabulary" do
      doc = slash_slot_doc({ name: "settings", kind: "kv", source: "config_keys", optional: true, repeatable: true })
      expect(described_class.validate(doc)).to eq([])
    end

    it "requires a kv slot to declare a source" do
      doc = slash_slot_doc({ name: "settings", kind: "kv" })
      expect(messages(doc)).to include(
        "tools.cfg.slash.slots[0].source: missing required key (kv slots need a source vocabulary)"
      )
    end

    it "accepts a `when:` conditional gating a slot on a prior slot's value" do
      doc = slash_slot_doc(
        { name: "state", kind: "enum", source: "on_off", optional: true, when: { provider: %w[sound] } }
      )
      expect(described_class.validate(doc)).to eq([])
    end

    it "rejects a non-Hash `when:` clause" do
      doc = slash_slot_doc({ name: "state", kind: "enum", source: "on_off", when: "sound" })
      expect(messages(doc)).to include("tools.cfg.slash.slots[0].when: expected a Hash, got String")
    end

    it "rejects a `when:` condition whose allowed values are not an Array" do
      doc = slash_slot_doc({ name: "state", kind: "enum", source: "on_off", when: { provider: "sound" } })
      expect(messages(doc)).to include(
        "tools.cfg.slash.slots[0].when.provider: expected an Array of allowed values, got String"
      )
    end

    it "rejects a non-scalar `when:` condition value" do
      doc = slash_slot_doc({ name: "state", kind: "enum", source: "on_off", when: { provider: [ %w[nested] ] } })
      expect(messages(doc)).to include(
        "tools.cfg.slash.slots[0].when.provider[0]: condition value must be a scalar, got Array"
      )
    end
  end

  describe ".validate — dispatch kinds (server class / client / controller)" do
    it "accepts a { controller: … } dispatch on an allow-listed action" do
      doc = valid_doc
      doc[:tools][:login] = { slash: { dispatch: { controller: "login" } } }
      expect(described_class.validate(doc)).to eq([])
    end

    it "rejects an unknown controller action and lists the allowed set" do
      doc = valid_doc
      doc[:tools][:x] = { slash: { dispatch: { controller: "nope" } } }
      expect(messages(doc)).to include(
        a_string_matching(/x\.slash\.dispatch\.controller: invalid controller action "nope" \(allowed: login, logout, connect, new, resume\)/)
      )
    end

    it "rejects a dispatch hash declaring neither client nor controller" do
      doc = valid_doc
      doc[:tools][:x] = { slash: { dispatch: { foo: "bar" } } }
      msgs = messages(doc)
      expect(msgs).to include("tools.x.slash.dispatch: dispatch hash must declare a client or controller action")
      expect(msgs).to include(a_string_matching(/x\.slash\.dispatch\.foo: unknown key/))
    end

    it "accepts a String dispatch naming a server handler class" do
      doc = valid_doc
      doc[:tools][:x] = { slash: { dispatch: "Slash::Handlers::Config" } }
      expect(described_class.validate(doc)).to eq([])
    end
  end

  describe ".validate — allow-listed names (predicates / resolvers / client actions)" do
    it "rejects an unknown emit_if predicate and suggests a near match" do
      doc = valid_doc
      doc[:tools][:show] = { segments: { game: { "x" => { builder: "B", kind: "enhanced", reply_target: "t", emit_if: "has_linked_video" } } } }
      expect(messages(doc)).to include(a_string_matching(/emit_if: unknown predicate "has_linked_video" \(did you mean has_linked_videos\?\)/))
    end

    it "rejects an unknown resolver name" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { t: { mode: "append", ref: { resolver: "no_such" } } } } }
      expect(messages(doc)).to include(a_string_matching(/ref\.resolver: unknown resolver "no_such"/))
    end

    it "accepts the source_entity resolver in a ref position" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_detail: { mode: "append", ref: { resolver: "source_entity" } } } } }
      expect(described_class.validate(doc)).to eq([])
    end

    it "accepts a named args entry whose value is a { resolver: … } Hash" do
      doc = valid_doc
      doc[:tools][:schedule] = {
        reply: { targets: { video_detail: { mode: "append",
                                            args: { when: { resolver: "schedule_expression" } } } } }
      }
      expect(described_class.validate(doc)).to eq([])
    end

    it "rejects an unknown resolver inside an args entry, naming the arg path" do
      doc = valid_doc
      doc[:tools][:x] = { reply: { targets: { t: { mode: "append", args: { when: { resolver: "no_such" } } } } } }
      expect(messages(doc)).to include(a_string_matching(/args\.when\.resolver: unknown resolver "no_such"/))
    end

    it "rejects an unknown key inside an args entry (only resolver is allowed)" do
      doc = valid_doc
      doc[:tools][:x] = { reply: { targets: { t: { mode: "append", args: { when: { resolver: "sort_clause", bogus: 1 } } } } } }
      expect(messages(doc)).to include(a_string_matching(/args\.when\.bogus: unknown key/))
    end

    it "rejects an unknown client dispatch action" do
      doc = valid_doc
      doc[:tools][:x] = { slash: { dispatch: { client: "nope" } } }
      expect(messages(doc)).to include(a_string_matching(/x\.slash\.dispatch\.client: invalid client action "nope"/))
    end
  end

  describe ".validate — tool-level shape" do
    it "requires every tool to declare at least one branch" do
      doc = valid_doc
      doc[:tools][:orphan] = { description: "pito.grammar.chat.show" }
      expect(messages(doc)).to include("tools.orphan: tool declares no branch (expected one of chat/slash/reply)")
    end

    it "reports a non-Hash tool body at its path" do
      doc = valid_doc
      doc[:tools][:weird] = "nope"
      expect(messages(doc)).to include("tools.weird: expected a Hash, got String")
    end

    it "requires schema_version and tools at the top level" do
      expect(messages({})).to include("schema_version: missing required key", "tools: missing required key")
    end
  end

  describe ".validate — universal_reply kinds: and except:" do
    def universal_doc(entry)
      doc = valid_doc
      doc[:universal_reply] = { share: { mode: "append" }.merge(entry) }
      doc
    end

    # ── kinds: ──────────────────────────────────────────────────────────────────

    it "accepts a valid kinds: array of event kinds" do
      expect(described_class.validate(universal_doc(kinds: %w[system enhanced]))).to eq([])
    end

    it "accepts a single-element kinds: array" do
      expect(described_class.validate(universal_doc(kinds: %w[system]))).to eq([])
    end

    it "rejects an unknown event kind in kinds: and lists the allowed set" do
      expect(messages(universal_doc(kinds: %w[magical]))).to include(
        a_string_matching(/universal_reply\.share\.kinds\[0\]: unknown event kind "magical" \(allowed:/)
      )
    end

    it "suggests a near-miss event kind name" do
      expect(messages(universal_doc(kinds: %w[syste]))).to include(
        a_string_matching(/universal_reply\.share\.kinds\[0\].*did you mean system\?/)
      )
    end

    it "rejects kinds: when it is not an Array" do
      expect(messages(universal_doc(kinds: "system"))).to include(
        "universal_reply.share.kinds: expected an Array, got String"
      )
    end

    # ── except: ─────────────────────────────────────────────────────────────────

    it "accepts a valid except: entry naming a reply target in the document" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_list: { mode: "append" } } } }
      doc[:universal_reply] = { share: { mode: "append", except: %w[game_list] } }
      expect(described_class.validate(doc)).to eq([])
    end

    it "accepts an empty except: array" do
      expect(described_class.validate(universal_doc(except: []))).to eq([])
    end

    it "rejects an except: entry that is not a declared reply target" do
      expect(messages(universal_doc(except: %w[no_such_target]))).to include(
        a_string_matching(/universal_reply\.share\.except\[0\]: unknown reply target "no_such_target"/)
      )
    end

    it "suggests a near-miss target name (did-you-mean) for except: entries" do
      doc = valid_doc
      doc[:tools][:show] = { reply: { targets: { game_list: { mode: "append" } } } }
      doc[:universal_reply] = { share: { mode: "append", except: %w[game_lis] } }
      expect(messages(doc)).to include(
        a_string_matching(/universal_reply\.share\.except\[0\].*did you mean game_list\?/)
      )
    end

    it "rejects except: when it is not an Array" do
      expect(messages(universal_doc(except: "game_list"))).to include(
        "universal_reply.share.except: expected an Array, got String"
      )
    end
  end

  describe ".validate — segment aliases" do
    # Build a doc with one or two segments in show/game.
    # A verb must declare at least one branch, so include a minimal chat branch.
    def segment_doc_with(segs)
      doc = valid_doc
      doc[:tools][:show] = { chat: { slots: [] }, segments: { game: segs } }
      doc
    end

    it "accepts a segment with a valid aliases array" do
      doc = segment_doc_with("detail" => { builder: "B", kind: "system", reply_target: "t",
                                           aliases: %w[alt-name] })
      expect(described_class.validate(doc)).to eq([])
    end

    it "accepts a segment with an empty aliases array" do
      doc = segment_doc_with("detail" => { builder: "B", kind: "system", reply_target: "t",
                                           aliases: [] })
      expect(described_class.validate(doc)).to eq([])
    end

    it "rejects a boolean alias token (HF2) with the quote hint" do
      doc = segment_doc_with("detail" => { builder: "B", kind: "system", reply_target: "t",
                                           aliases: [ false, "ok" ] })
      expect(messages(doc)).to include(
        a_string_matching(/segments\.game\.detail\.aliases\[0\]: boolean false — quote YAML-boolean tokens/)
      )
    end

    it "rejects a non-scalar alias token" do
      doc = segment_doc_with("detail" => { builder: "B", kind: "system", reply_target: "t",
                                           aliases: [ %w[nested] ] })
      expect(messages(doc)).to include(
        a_string_matching(/segments\.game\.detail\.aliases\[0\]: alias token must be a scalar/)
      )
    end

    it "rejects an alias that collides with another segment's canonical name" do
      doc = segment_doc_with(
        "detail"  => { builder: "B1", kind: "system",   reply_target: "t1" },
        "similar" => { builder: "B2", kind: "enhanced", reply_target: "t2",
                       aliases: %w[detail] }
      )
      expect(messages(doc)).to include(
        a_string_matching(/segments\.game\.similar\.aliases\[0\]: alias "detail" collides with segment/)
      )
    end

    it "does not flag an error when aliases are unique across all segments in the entity" do
      doc = segment_doc_with(
        "detail"  => { builder: "B1", kind: "system",   reply_target: "t1" },
        "similar" => { builder: "B2", kind: "enhanced", reply_target: "t2",
                       aliases: %w[similars] }
      )
      expect(described_class.validate(doc)).to eq([])
    end
  end

  describe ".validate — YAML-boolean token rejection (HF2)" do
    it "rejects a boolean alias token with the quote hint" do
      doc = valid_doc
      doc[:tools][:greet][:aliases] = [ false, "hi" ]
      expect(messages(doc)).to include(
        a_string_matching(/tools\.greet\.aliases\[0\]: boolean false — quote YAML-boolean tokens/)
      )
    end
  end

  describe ".validate — mcp blocks (G130, read-only tool ontology)" do
    # A well-formed mcp block on a chat verb; the verb keeps its chat branch so
    # only the mcp key is under test.
    def mcp_doc(mcp)
      doc = valid_doc
      doc[:tools][:show] = { chat: { slots: [] }, mcp: mcp }
      doc
    end

    MINIMAL_MCP = {
      tool:        "pito_show",
      description: "Show a game",
      read_only:   true,
      params:      { ref: { type: "string", required: true, hint: "numeric id" } },
      input:       "show %{ref}"
    }.freeze

    # ── INERTNESS: an mcp block is purely additive ────────────────────────────────
    it "a verb WITH a well-formed mcp block still validates clean" do
      expect(described_class.validate(mcp_doc(MINIMAL_MCP))).to eq([])
    end

    it "mcp is NOT a dispatch branch — a tool with only an mcp block declares none" do
      doc = valid_doc
      doc[:tools][:orphan] = { mcp: MINIMAL_MCP }
      expect(messages(doc)).to include("tools.orphan: tool declares no branch (expected one of chat/slash/reply)")
    end

    it "accepts input_suffixes plus array/enum params" do
      doc = mcp_doc(
        tool:           "pito_list",
        description:    "List things",
        read_only:      true,
        params:         { noun:    { type: "string", enum: %w[games vids], required: true },
                          columns: { type: "array", items: "string" } },
        input:          "list %{noun}",
        input_suffixes: { columns: " with %{values}" }
      )
      expect(described_class.validate(doc)).to eq([])
    end

    it "requires read_only on every mcp block (strict per-tool declaration)" do
      expect(messages(mcp_doc(MINIMAL_MCP.except(:read_only))))
        .to include("tools.show.mcp.read_only: missing required key")
    end

    it "rejects a non-boolean read_only" do
      expect(messages(mcp_doc(MINIMAL_MCP.merge(read_only: "yes"))))
        .to include(a_string_matching(/tools\.show\.mcp\.read_only: expected/))
    end

    # ── the walker catches malformed blocks ───────────────────────────────────────
    it "rejects an unknown key inside an mcp block (did-you-mean)" do
      expect(messages(mcp_doc(MINIMAL_MCP.merge(descriptn: "x"))))
        .to include(a_string_matching(/tools\.show\.mcp\.descriptn: unknown key \(did you mean description\?\)/))
    end

    it "requires tool and description" do
      expect(messages(mcp_doc(input: "show %{ref}")))
        .to include("tools.show.mcp.tool: missing required key",
                    "tools.show.mcp.description: missing required key")
    end

    it "rejects a param with an invalid type and lists the allowed set" do
      doc = mcp_doc(tool: "t", description: "d", params: { ref: { type: "stringg" } }, input: "x")
      expect(messages(doc))
        .to include(a_string_matching(/tools\.show\.mcp\.params\.ref\.type: invalid mcp param type "stringg"/))
    end

    it "requires each param to declare a type" do
      doc = mcp_doc(tool: "t", description: "d", params: { ref: { required: true } }, input: "x")
      expect(messages(doc)).to include("tools.show.mcp.params.ref.type: missing required key")
    end

    it "rejects a non-Array enum on a param" do
      doc = mcp_doc(tool: "t", description: "d", params: { noun: { type: "string", enum: "games" } }, input: "x")
      expect(messages(doc)).to include(a_string_matching(/tools\.show\.mcp\.params\.noun\.enum: expected an Array/))
    end

    it "rejects a non-string input template" do
      doc = mcp_doc(tool: "t", description: "d", input: 42)
      expect(messages(doc)).to include("tools.show.mcp.input: expected a String, got Integer")
    end

    # ── top-level mcp_readers section ─────────────────────────────────────────────
    it "accepts a well-formed mcp_readers section" do
      doc = valid_doc
      doc[:mcp_readers] = {
        pito_conversations: { tool: "pito_conversations", description: "list convos", read_only: true },
        pito_messages:      { tool: "pito_messages", description: "read msgs", read_only: true,
                              params: { limit: { type: "integer" } } }
      }
      expect(described_class.validate(doc)).to eq([])
    end

    it "rejects an unknown key inside an mcp_readers entry (input is verb-only)" do
      doc = valid_doc
      doc[:mcp_readers] = { r: { tool: "t", description: "d", input: "x" } }
      expect(messages(doc)).to include(a_string_matching(/mcp_readers\.r\.input: unknown key/))
    end

    it "requires an mcp_readers entry to declare tool and description" do
      doc = valid_doc
      doc[:mcp_readers] = { r: { params: {} } }
      expect(messages(doc)).to include("mcp_readers.r.tool: missing required key",
                                       "mcp_readers.r.description: missing required key")
    end
  end

  describe ".validate — capability blocks (v1.6 unified grammar)" do
    # A well-formed capabilities block on a chat verb; the verb keeps its chat
    # branch so only the capabilities key is under test.
    def cap_doc(capabilities)
      doc = valid_doc
      doc[:tools][:list] = { chat: { slots: [] }, capabilities: capabilities }
      doc
    end

    MINIMAL_CAP_COLUMN = { aliases: %w[title], desc: "pito.copy.column.title" }.freeze

    it "rejects a capabilities column declaring heading: (removed from CAP_COLUMN_KEYS)" do
      doc = cap_doc(columns: { games: { title: MINIMAL_CAP_COLUMN.merge(heading: "Title") } })
      expect(messages(doc)).to include("tools.list.capabilities.columns.games.title.heading: unknown key")
    end

    it "rejects a capabilities filter declaring neither tokens nor vocabulary" do
      doc = cap_doc(filters: { games: { upcoming: { desc: "d" } } })
      expect(messages(doc)).to include(
        "tools.list.capabilities.filters.games.upcoming: filter must declare tokens (non-empty Array) or vocabulary (String)"
      )
    end

    it "accepts a capabilities filter declaring only a non-empty tokens: array" do
      doc = cap_doc(filters: { games: { upcoming: { tokens: %w[x], desc: "d" } } })
      expect(described_class.validate(doc)).to eq([])
    end

    it "accepts a capabilities filter declaring only vocabulary:" do
      doc = cap_doc(filters: { games: { genre: { vocabulary: "genres", desc: "d" } } })
      expect(described_class.validate(doc)).to eq([])
    end
  end

  describe ".alias_collisions" do
    it "returns [] when no token repeats within a namespace" do
      doc = { tools: { foo: { chat: {}, aliases: [ "f" ] }, bar: { chat: {}, aliases: [ "b" ] } } }
      expect(described_class.alias_collisions(doc)).to eq([])
    end

    it "flags a token shared by two tools in the same namespace" do
      doc = { tools: { foo: { chat: {}, aliases: [ "x" ] }, bar: { chat: {}, aliases: [ "x" ] } } }
      collisions = described_class.alias_collisions(doc).map(&:to_s)
      expect(collisions).to include(a_string_matching(/\Achat:x: token maps to multiple tools \["bar", "foo"\]/))
    end

    it "does NOT flag the same token across different namespaces" do
      doc = { tools: { foo: { chat: {}, aliases: [ "x" ] }, baz: { slash: {}, aliases: [ "x" ] } } }
      expect(described_class.alias_collisions(doc)).to eq([])
    end

    it "places universal_reply tools in the reply namespace" do
      doc = { universal_reply: { share: { mode: "append" } },
              tools: { foo: { reply: { targets: {} }, aliases: [ "share" ] } } }
      collisions = described_class.alias_collisions(doc).map(&:to_s)
      expect(collisions).to include(a_string_matching(/\Areply:share: token maps to multiple tools \["foo", "share"\]/))
    end
  end

  describe ".suggest" do
    it "returns the closest allowed key within Levenshtein 2" do
      expect(described_class.suggest(:mod, %i[mode ref args])).to eq("mode")
    end

    it "returns nil when nothing is within the threshold" do
      expect(described_class.suggest(:zzzzz, %i[mode ref args])).to be_nil
    end
  end

  describe Pito::Dispatch::Schema::Error do
    it "renders as 'path: message'" do
      expect(described_class.new("tools.show.mode", "invalid").to_s).to eq("tools.show.mode: invalid")
    end
  end
end
