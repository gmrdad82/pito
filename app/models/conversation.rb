# frozen_string_literal: true

class Conversation < ApplicationRecord
  has_many :turns, -> { order(:position) }, dependent: :destroy
  has_many :events, -> { order(:position) }, dependent: :destroy

  def self.singleton
    first_or_create!
  end
end
