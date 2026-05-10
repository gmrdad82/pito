module Mcp
  module Tools
    class UpdateVideo < MCP::Tool
      tool_name "update_video"
      description "Update editable metadata on a video (title, description, tags, category_id, project_id, made_for_kids, synthetic_media, star). NOT for changing privacy_status or publish_at — use publish_video."

      input_schema(
        type: "object",
        properties: {
          id:                          { type: "string", description: "Video slug (youtube_video_id) or integer id (as string)" },
          title:                       { type: "string" },
          description:                 { type: "string" },
          tags:                        { type: "array", items: { type: "string" } },
          category_id:                 { type: "string" },
          project_id:                  { type: [ "integer", "null" ] },
          self_declared_made_for_kids: { type: "string", enum: [ "yes", "no" ] },
          contains_synthetic_media:    { type: "string", enum: [ "yes", "no" ] },
          star:                        { type: "string", enum: [ "yes", "no" ] },
          confirm:                     { type: "string", enum: [ "yes", "no" ], description: "two-step confirm; 'no' returns a dry-run preview" }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, confirm: "no", **input)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = begin
          Video.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("video not found: #{id}") unless video

        # Reject smuggle attempts explicitly.
        if input.key?(:privacy_status) || input.key?(:publish_at)
          return error_response("privacy_status and publish_at cannot be set via update_video; use publish_video.")
        end

        boolean_keys = %i[self_declared_made_for_kids contains_synthetic_media star]
        boolean_keys.each do |k|
          v = input[k]
          next if v.nil?
          return error_response("#{k} must be 'yes' or 'no' (got #{v.inspect})") unless YesNo.yes_no?(v)
        end

        attrs = {}
        attrs[:title]                       = input[:title]                       if input.key?(:title)
        attrs[:description]                 = input[:description]                 if input.key?(:description)
        attrs[:tags]                        = Array(input[:tags])                 if input.key?(:tags)
        attrs[:category_id]                 = input[:category_id]                 if input.key?(:category_id)
        attrs[:project_id]                  = input[:project_id]                  if input.key?(:project_id)
        attrs[:self_declared_made_for_kids] = YesNo.from_yes_no(input[:self_declared_made_for_kids]) if input.key?(:self_declared_made_for_kids)
        attrs[:contains_synthetic_media]    = YesNo.from_yes_no(input[:contains_synthetic_media])    if input.key?(:contains_synthetic_media)
        attrs[:star]                        = YesNo.from_yes_no(input[:star])                       if input.key?(:star)

        return error_response("no fields to update.") if attrs.empty?

        if YesNo.from_yes_no(confirm) == false
          changes = attrs.each_with_object({}) do |(k, v), out|
            old = video.public_send(k)
            old = YesNo.to_yes_no(old) if [ true, false ].include?(old)
            new_v = v
            new_v = YesNo.to_yes_no(new_v) if [ true, false ].include?(new_v)
            out[k] = { old: old, new: new_v }
          end
          payload = { video_id: video.id, changes: changes, hint: "re-run with confirm: 'yes' to apply." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        if video.update(attrs)
          data = VideoDecorator.new(video.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "video updated.\n#{JSON.pretty_generate(data)}" } ])
        else
          error_response("couldn't update video: #{video.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
