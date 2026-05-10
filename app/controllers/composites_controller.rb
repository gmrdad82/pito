# Phase 14 §2 — Composite cover serving controller.
#
# Auth-gated `/composites/:filename.jpg` route (master-agent decision
# #9). Composite covers are user data, not public assets. Serves the
# JPEG bytes from `<PITO_ASSETS_PATH>/composites/<filename>.jpg` with
# the correct content-type.
#
# The `:filename` route constraint pins the shape so path-traversal
# candidates never reach the action; the action layer reapplies the
# regex as defense-in-depth and resolves the path through
# `Pito::AssetsRoot.path` which validates lexical containment.
class CompositesController < ApplicationController
  FILENAME_REGEX = /\A[a-z_]+-\d+\z/.freeze

  def show
    name = params[:filename].to_s
    unless name.match?(FILENAME_REGEX)
      head :not_found
      return
    end

    path =
      begin
        Pito::AssetsRoot.path("composites", "#{name}.jpg")
      rescue Pito::AssetsRoot::Error
        head :not_found
        return
      end

    unless File.exist?(path)
      head :not_found
      return
    end

    send_file path.to_s, type: "image/jpeg", disposition: "inline"
  end
end
