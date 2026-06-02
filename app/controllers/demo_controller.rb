# frozen_string_literal: true

class DemoController < ApplicationController
  skip_before_action :authenticate_session!
  before_action { raise ActionController::RoutingError, "Not Found" unless Rails.env.development? }

  FakeEvent = Struct.new(:created_at, :id, :turn)

  def show
    @fake_event = FakeEvent.new(Time.zone.local(2026, 6, 2, 14, 32, 0), nil, nil)
  end
end
