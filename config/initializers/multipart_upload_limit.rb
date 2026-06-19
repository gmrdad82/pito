# Channel banner uploads.
#
# The banner spec allows JPEG/PNG up to 6MB. Rails/Rack 3 do not
# impose a per-part byte cap by default — uploads are gated by:
#
#   - nginx `client_max_body_size` (deployment-side; the matching
#     change lands in the ops playbook for this phase: bump to 10MB
#     to give headroom for 6MB banner + multipart envelope).
#   - Puma's `nakayoshi_fork` / worker-side memory ceilings (not
#     a per-request limit).
#   - `Rack::Utils.multipart_file_limit` — the number of file PARTS
#     per multipart request, NOT the bytes-per-part. Default 128;
#     a banner submit carries 1 file, so no change needed.
#
# This initializer pins the part-count limit explicitly so a
# misbehaving client cannot inflate it via env var, and documents
# the 10MB nginx target so the next person reading the upload path
# does not have to dig.
Rack::Utils.multipart_file_limit = 128 if Rack::Utils.respond_to?(:multipart_file_limit=)
