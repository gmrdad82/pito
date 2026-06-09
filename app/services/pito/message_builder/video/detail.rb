# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload Hash for a video-detail system event.
      #
      # Returns a Hash shaped for a system event (body + html: true) with
      # follow-up fields injected by Pito::FollowUp.make_followupable!.
      #
      # == Usage
      #
      #   payload = Pito::MessageBuilder::Video::Detail.call(video, conversation: conv)
      #   # => { "body" => "<div>...</div>", "html" => true, "reply_handle" => ..., "reply_target" => "video_detail" }
      #
      module Detail
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param video        [::Video]        the video record to render.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] system event payload with body, html: true, and follow-up fields.
        def call(video, conversation:)
          card_html = render_component(Pito::Video::DetailComponent.new(video: video))

          intro = Pito::Copy.render("pito.copy.video.detail_intro", { title: video.title })

          intro_html = %(<p class="text-fg mb-2">#{ERB::Util.html_escape(intro)}</p>)

          body = %(<div class="pito-video-detail-message">#{intro_html}#{card_html}</div>)

          payload = html_payload(body: body, video_id: video.id)

          Pito::FollowUp.make_followupable!(payload, target: "video_detail", conversation: conversation)

          payload
        end
      end
    end
  end
end
