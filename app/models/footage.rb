# frozen_string_literal: true

class Footage < ApplicationRecord
  belongs_to :game, optional: true

  validates :filename,   presence: true
  validates :local_path, presence: true, uniqueness: true
  validates :bit_depth,  inclusion: { in: [ 8, 10, 12 ] }
end
