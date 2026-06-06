# Abstract base for all pito ActiveJob jobs.
# Queue convention: default / analytics / bulk_sync / bulk_deletion
# per-job (set via `queue_as`). Retry and discard policies are declared
# on individual job classes as needed; no global policy is set here.
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
