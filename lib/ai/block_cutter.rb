# frozen_string_literal: true

module Ai
  # Incremental cutter over the STREAMING pito_respond arguments JSON —
  # `{"blocks": [ {…}, {…}, … ]}` arriving as arbitrary wire fragments
  # (SSE tool-call argument deltas). Feed fragments with `<<`; each COMPLETE
  # top-level block object is cut, as its raw JSON substring, the moment its
  # closing brace lands — no matter where the fragment boundaries fall
  # (mid-key, mid-string, mid-escape, mid-unicode-escape).
  #
  #   cutter = Ai::BlockCutter.new
  #   cutter << fragment   # any split point, any size
  #   cutter.take_blocks   # => ["{…}", …] blocks cut since last call (drains)
  #
  # Array detection (documented choice): the blocks array starts at the FIRST
  # `[` at object depth 1, outside strings. pito_respond's arguments schema
  # declares "blocks" as its ONLY top-level property (additionalProperties:
  # false — Ai::Toolset#respond_tool), so for well-formed payloads this
  # simple heuristic is exact and needs no key tokenizer; a `[` nested inside
  # a preceding value sits at depth >= 2 (or inside a string) and is skipped.
  #
  # A block runs from a `{` at array level to its matching `}` — brace depth
  # counted outside strings, string state honoring `\` escapes (`\uXXXX`
  # rides on the escaped `u`; the four hex chars are plain string content).
  # Whitespace and commas between blocks are ignored; content before the
  # array and after its closing `]` is ignored. Malformed input NEVER raises
  # — the cutter goes dead and stops yielding (end-of-stream full-payload
  # validation is the real gate; this class only feeds the live preview).
  #
  # PARTIAL SNAPSHOT (row-level streaming): while a block is in progress,
  # `take_partial` yields the newest auto-closed snapshot of it, taken at
  # each element boundary of the block's first array-valued key (e.g. a
  # `kv_table`/`table` row, whether the row is itself an array or an
  # object) — the buffer plus the closing `]}` it's missing. It's a live
  # preview the consumer filters by block `type` before rendering rows
  # incrementally; it drains on read like `take_blocks`, and is cleared the
  # moment the block's own final `}` cuts it, so nothing stale survives past
  # the complete block.
  #
  # Pure Ruby, no Rails dependencies.
  class BlockCutter
    def initialize
      @phase  = :before_array # :before_array → :between_blocks ⇄ :in_block → :done | :dead
      @depth  = 0             # object-brace depth (outer object, then within-block)
      @string = false         # inside a JSON string?
      @escape = false         # previous string char an escape backslash?
      @buffer = +""
      @cut    = []

      @block_stack = [] # "{" / "[" stack within the in-progress block (partial-snapshot bookkeeping)
      @partial     = nil # newest auto-closed partial snapshot of the in-progress block
    end

    # Feed the next fragment (any split point, any size). Returns self.
    def <<(fragment)
      fragment.to_s.each_char { |char| scan(char) }
      self
    end

    # Complete block-object JSON strings cut since the last call — drains,
    # so a second immediate call returns [].
    def take_blocks
      out = @cut
      @cut = []
      out
    end

    # Newest partial snapshot of the in-progress block recorded since the
    # last call — drains, so a second immediate call returns nil. nil when
    # no element boundary has been crossed yet (or the block already cut).
    def take_partial
      out = @partial
      @partial = nil
      out
    end

    private

    def scan(char)
      case @phase
      when :before_array   then before_array(char)
      when :between_blocks then between_blocks(char)
      when :in_block       then in_block(char)
      end # :done / :dead — everything is ignored
    end

    # Hunting for the first `[` at object depth 1 (see class doc). String
    # state is tracked so a `[`, `{`, or `}` inside a preceding string value
    # never counts as structure.
    def before_array(char)
      return if string_char?(char)

      case char
      when "{" then @depth += 1
      when "}"
        @depth -= 1
        @phase = :dead if @depth <= 0 # outer object closed (or never opened) without a blocks array
      when "["
        @phase = :between_blocks if @depth == 1
      end
    end

    # At array level: `{` opens a block, `]` closes the array, whitespace and
    # commas separate; anything else means this is not an array of objects —
    # go dead rather than guess.
    def between_blocks(char)
      case char
      when "{"
        @phase = :in_block
        @depth = 1
        @block_stack = [ "{" ]
        @buffer << char
      when "]"
        @phase = :done
      when " ", "\t", "\n", "\r", ","
        # inter-block filler — ignored
      else
        @phase = :dead
      end
    end

    # Inside a block every char is buffered verbatim; only braces OUTSIDE
    # strings move the depth. The matching `}` (depth back to zero) cuts the
    # buffer as one complete block. Alongside `@depth`, `@block_stack` tracks
    # the actual "{" / "[" nesting so a non-completing `}`/`]` can tell
    # whether it just closed an element of the block's first array-valued
    # key (see `snapshot_partial`).
    def in_block(char)
      @buffer << char
      return if string_char?(char)

      case char
      when "{"
        @depth += 1
        @block_stack.push("{")
      when "["
        @block_stack.push("[")
      when "}"
        @depth -= 1
        @block_stack.pop
        if @depth.zero?
          @cut << @buffer
          @buffer = +""
          @phase = :between_blocks
          @block_stack = []
          @partial = nil
        else
          snapshot_partial
        end
      when "]"
        @block_stack.pop
        snapshot_partial
      end
    end

    # After a closing `}`/`]` pops the stack without completing the block:
    # if exactly one array level sits directly under the block object
    # (stack == ["{", "["]), the buffer just crossed an element boundary of
    # the block's first array-valued key — auto-close it (missing `]` then
    # `}`) and record it as the newest partial, overwriting any prior one.
    def snapshot_partial
      @partial = "#{@buffer}]}" if @block_stack == [ "{", "[" ]
    end

    # The JSON-string state machine. Returns true when the char belongs to a
    # string (content, its opening/closing quote, or an escape pair), so
    # callers never treat quoted braces/brackets/commas as structure.
    def string_char?(char)
      if @string
        if @escape
          @escape = false # the escaped char (", \, u of \uXXXX, …) is plain content
        elsif char == "\\"
          @escape = true
        elsif char == '"'
          @string = false
        end
        true
      elsif char == '"'
        @string = true
        true
      else
        false
      end
    end
  end
end
