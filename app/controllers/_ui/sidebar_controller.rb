# frozen_string_literal: true

module Ui
  class SidebarController < ApplicationController
    allow_anonymous :show

    def show
      @events = Pito::Sample::ChatShell.events
      @game = Pito::Sample::GameDetail.game
    end
  end
end
