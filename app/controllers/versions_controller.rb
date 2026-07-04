# frozen_string_literal: true

# VersionsController — the running build's identity for the refresh nudge
# (G71): pito--cable-health fetches this after a cable reconnect and compares
# it with the page's `pito-version` meta; a mismatch means the server was
# updated under the open tab. Auth-required on purpose: the nudge only matters
# on authenticated pages, and anonymous visitors get the standard JSON 401
# instead of a version disclosure.
class VersionsController < ApplicationController
  def show
    render json: { version: Pito::Version.suffix }
  end
end
