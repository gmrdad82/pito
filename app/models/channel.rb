# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy

  validates :youtube_channel_id,
            presence: true,
            uniqueness: { case_sensitive: true }
end
