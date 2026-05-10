module Mcp
  module Tools
    class PublishVideo < MCP::Tool
      tool_name "publish_video"
      description "Publish a private video, OR schedule a future publish. Requires the four pre-publish-checklist booleans + pre_publish_checked_at to be set first (call pre_publish_check_video). target=public|unlisted|scheduled."

      input_schema(
        type: "object",
        properties: {
          id:         { type: "integer", description: "Video ID" },
          target:     { type: "string", enum: [ "public", "unlisted", "scheduled" ] },
          publish_at: { type: "string", description: "ISO 8601 timestamp; required when target=scheduled." },
          confirm:    { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id", "target" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, target:, publish_at: nil, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = Video.find_by(id: id)
        return error_response("video not found: #{id}") unless video

        unless %w[public unlisted scheduled].include?(target.to_s)
          return error_response("target must be 'public', 'unlisted', or 'scheduled'")
        end

        unless video.privacy_private?
          return error_response("video is already #{video.privacy_status}; only private videos can be published.")
        end

        unless video.pre_publish_complete?
          missing = []
          missing << "game_ok" unless video.pre_publish_game_ok?
          missing << "age_ok" unless video.pre_publish_age_ok?
          missing << "paid_promotion_ok" unless video.pre_publish_paid_promotion_ok?
          missing << "end_screen_ok" unless video.pre_publish_end_screen_ok?
          missing << "pre_publish_checked_at" if video.pre_publish_checked_at.nil?
          return error_response("pre-publish checklist incomplete: missing #{missing.join(', ')}. call pre_publish_check_video first.")
        end

        if target.to_s == "scheduled"
          return error_response("publish_at is required when target=scheduled.") if publish_at.blank?
          parsed = parse_publish_at(publish_at)
          return error_response("publish_at must be a valid ISO 8601 timestamp.") if parsed.nil?
          return error_response("publish_at must be in the future.") if parsed <= Time.current
        end

        if YesNo.from_yes_no(confirm) == false
          payload = {
            video_id: video.id,
            current: { privacy_status: video.privacy_status, publish_at: video.publish_at&.iso8601 },
            proposed: { target: target, publish_at: publish_at },
            hint: "re-run with confirm: 'yes' to apply."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        attrs = if target.to_s == "scheduled"
                  { publish_at: parse_publish_at(publish_at), privacy_status: :private }
        else
                  { privacy_status: target.to_sym, published_at: video.published_at || Time.current }
        end

        if video.update(attrs)
          data = VideoDecorator.new(video.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "video published.\n#{JSON.pretty_generate(data)}" } ])
        else
          error_response("couldn't publish video: #{video.errors.full_messages.join(', ')}")
        end
      end

      def self.parse_publish_at(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
