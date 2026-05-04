class Video < ApplicationRecord
  include Searchable

  belongs_to :channel

  has_many :video_stats, dependent: :destroy
  has_many :playlist_items, dependent: :destroy
  has_many :playlists, through: :playlist_items

  # Phase 4 §11.2 — the spec asks for an aasm machine "scheduled → published
  # → unpublished" mapped onto `videos.privacy_status (existing integer)" and
  # prefaces it with "Confirm enum mapping before adding aasm." The mapping
  # CANNOT be confirmed cleanly: the existing enum stores YouTube visibility
  # (`public_video` / `unlisted` / `private_video`), which is a different
  # axis from the aasm lifecycle. AASM and AR enum on the same column read
  # the column back as the enum string ("public_video"), then AASM tries to
  # find a state with that name and fails ("Privacy status is invalid").
  #
  # Resolution (logged for the architect's review): defer the Video aasm
  # machine until we either (a) add a separate `lifecycle_state` column or
  # (b) commit to renaming the enum. Phase A's Timeline aasm covers the
  # state-machine acceptance criterion; Video aasm is a follow-up.
  enum :privacy_status, { public_video: 0, unlisted: 1, private_video: 2 }

  validates :youtube_video_id, presence: true, uniqueness: { case_sensitive: false }
  validates :title, presence: true

  searchable :title, :description, :tags, :category_id, :default_language
  filterable :channel_id, :privacy_status
end
