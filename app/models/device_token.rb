# frozen_string_literal: true

class DeviceToken < ApplicationRecord
  validates :token, presence: true, uniqueness: true
end
