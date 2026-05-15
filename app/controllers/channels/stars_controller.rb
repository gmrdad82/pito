module Channels
  # Unit A0 — channel is a read-only mirror; `star` is the single
  # mutable channel attribute. This controller owns the only channel
  # write path. PATCH /channels/:channel_id/star.
  #
  # Boundary contract (CLAUDE.md): the `star` value arrives as the
  # string "yes" / "no" — never true/false/0/1. Internal storage is
  # Boolean; conversion happens here. The HTML caller (the inline
  # [star]/[unstar] form on the pane) and the JSON caller (pito CLI)
  # both send `channel[star]` as "yes"/"no".
  #
  # The route is a singular `star` resource nested in the `:channels`
  # member block, so the channel id arrives as `params[:id]` (not
  # `:channel_id`).
  class StarsController < ApplicationController
    skip_before_action :verify_authenticity_token,
                       if: -> { request.format.json? }

    def update
      @channel = Channel.friendly.find(params[:id])

      raw = params.dig(:channel, :star)
      unless YesNo.yes_no?(raw)
        message = "star must be 'yes' or 'no' (got #{raw.inspect})"
        respond_to do |format|
          format.html { redirect_to channel_path(@channel), alert: message }
          format.json do
            render json: { errors: [ message ] },
                   status: :unprocessable_content
          end
        end
        return
      end

      if @channel.update(star: YesNo.from_yes_no(raw))
        respond_to do |format|
          format.html do
            redirect_to channel_path(@channel), notice: "channel updated."
          end
          format.json do
            render json: ChannelDecorator.new(@channel).as_detail_json
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to channel_path(@channel), alert: "could not update channel." }
          format.json do
            render json: { errors: @channel.errors.full_messages },
                   status: :unprocessable_content
          end
        end
      end
    end
  end
end
