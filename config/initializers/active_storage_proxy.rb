# frozen_string_literal: true

# Serve ActiveStorage attachments through the app (proxy delivery) instead of
# redirecting the browser to the storage service. Paired with Pito::ImagePath's
# host-less proxy paths, this lets attachment images load from ANY host serving
# the app (plain localhost, an off-box tunnel like app.pitomd.com, production)
# without baking a scheme/host into the generated URL.
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy
