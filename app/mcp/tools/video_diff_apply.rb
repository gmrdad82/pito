module Mcp
  module Tools
    # Phase 23 §23c — MCP tool: apply per-field decisions to the open
    # video diff. Two-step confirm flag per the project's hard rule.
    # Body shape:
    #   {
    #     "id":        "<video slug or integer id>",
    #     "decisions": { "<field>": "pito" | "youtube", ... },
    #     "confirm":   "yes" | "no"
    #   }
    # `decisions` covers every field in the diff payload; the apply
    # service rejects partial decisions. Boundary booleans use yes/no
    # strings per the project rule — even though the decision values
    # themselves are "pito" / "youtube" (locked spec language).
    class VideoDiffApply < MCP::Tool
      tool_name "video_diff_apply"
      description "Resolve a video's open YouTube diff. Per-field decisions: 'pito' pushes the local value to YouTube; 'youtube' pulls the remote value to Pito. Requires confirm='yes' to apply (the unconfirmed call returns a preview)."

      input_schema(
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "Video slug (youtube_video_id) or integer id (as string)"
          },
          decisions: {
            type: "object",
            description: "Per-field decision hash: { '<field>': 'pito' | 'youtube' }. Every field in the diff must carry a decision.",
            additionalProperties: { type: "string", enum: [ "pito", "youtube" ] }
          },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "Must be 'yes' to actually apply. 'no' or omitted returns a preview only."
          }
        },
        required: [ "id", "decisions" ]
      )

      annotations(read_only_hint: false)

      def self.call(id:, decisions:, confirm: nil)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = begin
          Video.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("video not found: #{id}") unless video

        diff = video.open_diff
        return error_response("no open diff for video: #{id}") unless diff

        normalized = normalize_decisions(decisions)

        if confirm.to_s.downcase != "yes"
          preview = {
            preview: true,
            video_id: video.id,
            video_slug: video.to_param,
            diff_id: diff.id,
            decisions: normalized,
            message: "preview — pass confirm='yes' to apply"
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(preview) } ])
        end

        result = Youtube::VideoDiffApply.call(
          video_diff: diff,
          decisions: normalized,
          user: Current.user
        )

        if result.success?
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(
            ok: true,
            diff_id: result.diff.id,
            pito_wins_fields: result.pito_wins_fields,
            youtube_wins_fields: result.youtube_wins_fields
          ) } ])
        else
          error_response("apply failed: #{result.error_code}: #{result.error_message}")
        end
      end

      def self.normalize_decisions(input)
        return {} if input.nil?

        case input
        when Hash
          input.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
        else
          {}
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
