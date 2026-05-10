module Mcp
  module Tools
    class PrePublishCheckVideo < MCP::Tool
      tool_name "pre_publish_check_video"
      description "Run the four-item pre-publish checklist for a video. Sets game_ok, age_ok, paid_promotion_ok, end_screen_ok and stamps pre_publish_checked_at. Does NOT publish — that's publish_video."

      input_schema(
        type: "object",
        properties: {
          id:                { type: "integer", description: "Video ID" },
          game_ok:           { type: "string", enum: [ "yes", "no" ] },
          age_ok:            { type: "string", enum: [ "yes", "no" ] },
          paid_promotion_ok: { type: "string", enum: [ "yes", "no" ] },
          end_screen_ok:     { type: "string", enum: [ "yes", "no" ] },
          confirm:           { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id", "game_ok", "age_ok", "paid_promotion_ok", "end_screen_ok" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, game_ok:, age_ok:, paid_promotion_ok:, end_screen_ok:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = Video.find_by(id: id)
        return error_response("video not found: #{id}") unless video

        { game_ok: game_ok, age_ok: age_ok,
          paid_promotion_ok: paid_promotion_ok,
          end_screen_ok: end_screen_ok }.each do |key, value|
          unless YesNo.yes_no?(value)
            return error_response("#{key} must be 'yes' or 'no' (got #{value.inspect})")
          end
        end

        attrs = {
          pre_publish_game_ok: YesNo.from_yes_no(game_ok),
          pre_publish_age_ok: YesNo.from_yes_no(age_ok),
          pre_publish_paid_promotion_ok: YesNo.from_yes_no(paid_promotion_ok),
          pre_publish_end_screen_ok: YesNo.from_yes_no(end_screen_ok),
          pre_publish_checked_at: Time.current
        }

        if YesNo.from_yes_no(confirm) == false
          payload = {
            video_id: video.id,
            current: {
              pre_publish_game_ok: YesNo.to_yes_no(video.pre_publish_game_ok),
              pre_publish_age_ok: YesNo.to_yes_no(video.pre_publish_age_ok),
              pre_publish_paid_promotion_ok: YesNo.to_yes_no(video.pre_publish_paid_promotion_ok),
              pre_publish_end_screen_ok: YesNo.to_yes_no(video.pre_publish_end_screen_ok)
            },
            proposed: {
              pre_publish_game_ok: game_ok,
              pre_publish_age_ok: age_ok,
              pre_publish_paid_promotion_ok: paid_promotion_ok,
              pre_publish_end_screen_ok: end_screen_ok
            },
            hint: "re-run with confirm: 'yes' to apply."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        if video.update(attrs)
          data = VideoDecorator.new(video.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "pre-publish checklist applied.\n#{JSON.pretty_generate(data)}" } ])
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
