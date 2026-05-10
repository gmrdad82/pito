module Mcp
  module Tools
    # Phase 14 §3 — link a Video to a Bundle.
    class VideoLinkBundle < MCP::Tool
      tool_name "video_link_bundle"
      description "Link a video to a bundle. is_primary is a 'yes'/'no' analytics-weighting hint."

      input_schema(
        type: "object",
        properties: {
          video_id: { type: "integer" },
          bundle_id: { type: "integer" },
          is_primary: { type: "string", enum: [ "yes", "no" ] },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "video_id", "bundle_id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(video_id:, bundle_id:, is_primary: "no", confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)
        return error_response("is_primary must be 'yes' or 'no' (got #{is_primary.inspect})") unless YesNo.yes_no?(is_primary)

        video = Video.find_by(id: video_id)
        return error_response("video not found: #{video_id}") unless video
        bundle = Bundle.find_by(id: bundle_id)
        return error_response("bundle not found: #{bundle_id}") unless bundle

        if video.video_game_links.exists?(bundle_id: bundle.id)
          return error_response("already linked.")
        end

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, video_id: video.id, bundle_id: bundle.id,
                      is_primary: is_primary,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        link = video.video_game_links.create(
          link_type: :bundle,
          bundle_id: bundle.id,
          is_primary: YesNo.from_yes_no(is_primary)
        )
        if link.persisted?
          payload = { id: link.id, video_id: video.id, bundle_id: bundle.id,
                      is_primary: YesNo.to_yes_no(link.is_primary),
                      message: "video linked to bundle." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't link: #{link.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
