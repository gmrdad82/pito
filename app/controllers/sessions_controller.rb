# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_anonymous :destroy

  def destroy
    Pito::Auth::SessionCookie.new(request).clear!
    redirect_to root_path
  end
end
