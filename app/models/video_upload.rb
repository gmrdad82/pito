class VideoUpload < ApplicationRecord
  belongs_to :channel
  belongs_to :video, optional: true

  enum :status, { pending: 0, uploading: 1, processing: 2, completed: 3, failed: 4 }
  enum :privacy_status, { public_video: 0, unlisted: 1, private_video: 2 }, prefix: :privacy

  validates :title, presence: true
  validates :file_name, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }

  def progress_percent
    return 0 if file_size.zero?
    ((bytes_sent.to_f / file_size) * 100).round(1)
  end
end
