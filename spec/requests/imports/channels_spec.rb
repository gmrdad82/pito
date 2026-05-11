require "rails_helper"

# Phase 22 §5 — Imports::ChannelsController request specs.
#
# Every action gets the happy / sad / edge / flaw sweep called for in
# the architect rule D spec pyramid. The job side is stubbed
# (Sidekiq::Testing.fake!) so we can assert on enqueue and on the
# ImportJob row state without running real Sidekiq workers.
RSpec.describe "Imports::Channels", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)       { User.first || create(:user) }
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }

  before do
    Rails.cache.clear
  end

  describe "GET /imports/channels" do
    it "renders the channel selection step (HTML)" do
      channel
      get imports_channels_path
      expect(response).to have_http_status(:ok)
      # Phase 22 polish — heading is now the `[videos] · [import]`
      # breadcrumb; the literal "import videos" string is gone. The
      # submit button copy is the bare verb `[import]` (no "start").
      expect(response.body).to include("channel_ids[]")
    end

    it "lists only connected channels" do
      connected = create(:channel, youtube_connection: connection)
      _bare = create(:channel)
      get imports_channels_path
      expect(response.body).to include("value=\"#{connected.id}\"")
    end

    it "disables the checkbox for channels with an in-flight job" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      get imports_channels_path
      # The checkbox is rendered with `disabled` and no `name`.
      expect(response.body).to include("disabled")
      expect(response.body).to include("import running")
    end

    # Phase 22 polish — four visual fixes on the channel-pick step:
    # 1. Native checkboxes replaced with bracketed `[ ]` / `[x]` style
    #    (CheckboxComponent + `.md-check-indicator` pseudo-element).
    # 2. Rightmost column gets a header label ("status") — it surfaces
    #    in-flight `[import running]` links.
    # 3. Submit button copy `[start import]` → `[import]` (bare verb;
    #    the heading already supplies "import" context).
    # 4. Page heading restructured to `[videos] · [import]` breadcrumb
    #    where `[import]` is the active label (plain span, not a link).
    describe "Phase 22 polish (bracketed checkbox / column header / button copy / breadcrumb)" do
      before { channel }

      it "renders bracketed-style checkboxes (no bare native input style)" do
        get imports_channels_path
        # CheckboxComponent wraps the input in a `label.md-check` plus a
        # `span.md-check-indicator` that renders the `[ ]` glyph via CSS.
        expect(response.body).to include('class="md-check"')
        expect(response.body).to include('class="md-check-indicator"')
      end

      it "labels the rightmost column header as 'status'" do
        get imports_channels_path
        expect(response.body).to match(%r{<th>\s*status\s*</th>})
      end

      it "renders the submit button as [import] (not [start import])" do
        get imports_channels_path
        expect(response.body).to include('<span class="bl">import</span>')
        expect(response.body).not_to include('<span class="bl">start import</span>')
        expect(response.body).not_to match(/\[\s*start import\s*\]/)
      end

      it "renders the heading as the breadcrumb [videos] · [import]" do
        get imports_channels_path
        # `[videos]` is a real link back to /videos.
        expect(response.body).to match(
          %r{<a [^>]*href="#{Regexp.escape(videos_path)}"[^>]*>\[<span class="bl">videos</span>\]</a>}
        )
        # The mid-dot separator partial.
        expect(response.body).to include("·")
        # `[import]` is the active span — plain text, not a link.
        expect(response.body).to include('<span class="bracketed-active">[import]</span>')
        # And the old literal heading "import videos" is gone.
        expect(response.body).not_to match(/<h1[^>]*>\s*import videos\s*<\/h1>/)
      end

      it "still surfaces the [import running] badge in the status column for in-flight channels" do
        ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
        get imports_channels_path
        expect(response.body).to include("import running")
      end
    end

    # Phase 22 fix — the `[import]` submit button is wired through the
    # `imports-select` Stimulus controller. The button ships disabled
    # and flips enabled when any `channel_ids[]` checkbox is checked.
    # Without the controller present in the DOM the button stays
    # disabled forever and clicking `[import]` does nothing.
    describe "imports-select Stimulus wiring" do
      before { channel }

      it "registers the imports-select controller on the form" do
        get imports_channels_path
        expect(response.body).to include('data-controller="imports-select"')
      end

      it "wires checkboxes as imports-select#refresh targets" do
        get imports_channels_path
        expect(response.body).to include('data-imports-select-target="checkbox"')
        # `>` is HTML-escaped to `&gt;` inside the `data-action` attribute
        # when the CheckboxComponent serializes the hash. Either form means
        # Stimulus will parse the same action descriptor.
        expect(response.body).to match(/change-(?:>|&gt;)imports-select#refresh/)
      end

      it "wires the submit button as the imports-select#submit target" do
        get imports_channels_path
        expect(response.body).to include('data-imports-select-target="submit"')
      end

      it "ships the submit button disabled so an empty submit is impossible" do
        get imports_channels_path
        expect(response.body).to match(
          %r{<button[^>]*data-imports-select-target="submit"[^>]*\bdisabled\b}
        )
      end
    end

    it "renders an empty state when no connected channels" do
      Channel.destroy_all
      get imports_channels_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no connected channels")
    end

    it "redirects unauthenticated callers to /login", :unauthenticated do
      get imports_channels_path
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
    end

    it "returns JSON when requested" do
      channel
      get imports_channels_path, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["channels"]).to be_an(Array)
      expect(body["channels"].first.keys).to include("id", "slug", "label",
                                                      "connected", "in_flight")
      expect(body["channels"].first["connected"]).to eq("yes")
      expect(body["channels"].first["in_flight"]).to eq("no")
    end

    it "serializes in_flight as yes/no when a job is queued" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
      get imports_channels_path, headers: { "Accept" => "application/json" }
      body = JSON.parse(response.body)
      entry = body["channels"].find { |c| c["id"] == channel.id }
      expect(entry["in_flight"]).to eq("yes")
      expect(entry["in_flight_job_id"]).to be_present
    end
  end

  describe "POST /imports/channels" do
    it "creates an ImportJob and enqueues the Sidekiq worker" do
      channel
      expect {
        post imports_channels_path, params: { channel_ids: [ channel.id ] }
      }.to change(ImportJob, :count).by(1)
        .and change(Channel::ImportVideosJob.jobs, :size).by(1)

      job = ImportJob.last
      expect(job.status).to eq("queued")
      expect(job.enqueued_by).to eq(user)
      expect(job.channel).to eq(channel)
    end

    it "creates one ImportJob per channel id" do
      channel
      second = create(:channel, youtube_connection: connection)
      expect {
        post imports_channels_path, params: { channel_ids: [ channel.id, second.id ] }
      }.to change(ImportJob, :count).by(2)
    end

    it "refuses a second enqueue when one is already in flight (locked decision #1)" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      expect {
        post imports_channels_path, params: { channel_ids: [ channel.id ] }
      }.not_to change(ImportJob, :count)
      # HTML branch redirects with flash; JSON branch returns 422.
      expect(response).to have_http_status(:found)
      follow_redirect!
      expect(flash[:alert]).to include("already running")
    end

    it "refuses a second enqueue (JSON) with 422" do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      post imports_channels_path, params: { channel_ids: [ channel.id ] },
                                  headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    context "rate-limit cache lock" do
      let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

      before { allow(Rails).to receive(:cache).and_return(memory_cache) }

      it "writes a 5-second per-user lock on the first request" do
        channel
        post imports_channels_path, params: { channel_ids: [ channel.id ] }
        user_id = User.first.id
        expect(memory_cache.exist?("imports:enqueue:user:#{user_id}")).to be(true)
      end

      it "redirects with an alert when the lock is held (HTML)" do
        user_id = User.first.id
        memory_cache.write("imports:enqueue:user:#{user_id}", 1, expires_in: 5.seconds)

        channel
        post imports_channels_path, params: { channel_ids: [ channel.id ] }
        expect(response).to redirect_to(videos_path)
        follow_redirect!
        expect(flash[:alert]).to include("try again in a moment")
      end

      it "returns 429 + rate_limited JSON envelope when the lock is held" do
        user_id = User.first.id
        memory_cache.write("imports:enqueue:user:#{user_id}", 1, expires_in: 5.seconds)

        channel
        post imports_channels_path, params: { channel_ids: [ channel.id ] },
                                    headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:too_many_requests)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("rate_limited")
        expect(body["retry_after_seconds"]).to eq(5)
      end

      it "does NOT enqueue when rate-limited" do
        user_id = User.first.id
        memory_cache.write("imports:enqueue:user:#{user_id}", 1, expires_in: 5.seconds)

        channel
        expect {
          post imports_channels_path, params: { channel_ids: [ channel.id ] }
        }.not_to change(ImportJob, :count)
      end
    end

    it "rejects empty channel_ids with 422" do
      post imports_channels_path, params: { channel_ids: [] }
      expect(response).to have_http_status(:found)
      # JSON branch returns 422.
      Rails.cache.clear
      post imports_channels_path, params: { channel_ids: [] },
                                  headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects unknown channel ids with errors" do
      channel
      post imports_channels_path, params: { channel_ids: [ "99999" ] },
                                  headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["errors"].first).to include("channel not found")
    end

    it "returns 201 JSON with the enqueued ImportJob payload" do
      channel
      post imports_channels_path, params: { channel_ids: [ channel.id ] },
                                  headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["import_jobs"]).to be_an(Array)
      expect(body["import_jobs"].first["in_flight"]).to eq("yes")
      expect(body["import_jobs"].first["status"]).to eq("queued")
    end

    it "returns multi-status 207 when some channels were refused", :aggregate_failures do
      good_channel = create(:channel, youtube_connection: connection)
      stuck_channel = create(:channel, youtube_connection: connection)
      ImportJob.create!(channel: stuck_channel, enqueued_by: user, status: :running)

      post imports_channels_path, params: { channel_ids: [ good_channel.id, stuck_channel.id ] },
                                  headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:multi_status)
      body = JSON.parse(response.body)
      expect(body["import_jobs"].length).to eq(1)
      expect(body["errors"].first).to include("already running")
    end
  end

  describe "GET /imports/channels/:id" do
    let(:running_job) do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :running,
                        started_at: 1.minute.ago)
    end
    let(:completed_job) do
      ImportJob.create!(channel: channel, enqueued_by: user, status: :completed,
                        started_at: 2.minutes.ago, completed_at: Time.current,
                        total_videos: 2, imported_videos: 2)
    end

    it "renders the progress block when the job is still running" do
      get imports_channel_path(running_job)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("import job ##{running_job.id}")
      expect(response.body).to include("imported 0 of 0")
    end

    it "renders the keep/reject table when the job is completed" do
      # Create job in :running first, then a video, then mark complete
      # so the candidate_videos window encloses the video.
      job = ImportJob.create!(channel: channel, enqueued_by: user, status: :running,
                              started_at: 1.minute.ago)
      created_video = create(:video, channel: channel, title: "Probe Title XYZ")
      job.update!(status: :completed, completed_at: 1.minute.from_now,
                  total_videos: 1, imported_videos: 1)

      get imports_channel_path(job)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("keep what to import")
      # Either the title (when present) or the youtube_video_id renders
      # per the keep/reject partial — assert the row was emitted.
      expect(response.body).to include("Probe Title XYZ")
      expect(response.body).to include("value=\"#{created_video.id}\"")
    end

    it "returns JSON with the full payload" do
      completed_job
      get imports_channel_path(completed_job), headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["import_job"]["status"]).to eq("completed")
      expect(body["import_job"]["in_flight"]).to eq("no")
      expect(body["candidate_videos"]).to be_an(Array)
    end

    it "404s for missing ids" do
      get imports_channel_path("99999")
      expect(response).to have_http_status(:not_found)
    end

    it "allows cross-user access (single-install architecture)" do
      other_user = create(:user)
      other_job = ImportJob.create!(channel: channel, enqueued_by: other_user, status: :queued)
      get imports_channel_path(other_job)
      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated callers", :unauthenticated do
      job = ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
      get imports_channel_path(job)
      expect(response).to have_http_status(:found)
    end
  end

  describe "PATCH /imports/channels/:id (keep / reject)" do
    # Freeze a deterministic window so the candidate_videos scope
    # picks up exactly the three test videos. The ImportJob is created
    # FIRST so its started_at < the three video created_at timestamps.
    let(:completed_job) do
      job = ImportJob.create!(channel: channel, enqueued_by: user, status: :running,
                              started_at: 5.minutes.ago)
      # Mark completed AFTER the videos are created (in the let! below).
      job
    end

    let!(:video_keep)    { create(:video, channel: channel, youtube_video_id: "keepAAAAAAA") }
    let!(:video_reject1) { create(:video, channel: channel, youtube_video_id: "rej1AAAAAAA") }
    let!(:video_reject2) { create(:video, channel: channel, youtube_video_id: "rej2AAAAAAA") }

    before do
      # Stamp the job complete now that the videos exist; the window
      # [started_at .. completed_at] now encloses all three.
      completed_job.update!(status: :completed,
                            completed_at: Time.current,
                            total_videos: 3, imported_videos: 3)
    end

    it "destroys un-kept videos and tombstones them" do
      expect {
        patch imports_channel_path(completed_job), params: { keep_video_ids: [ video_keep.id ] }
      }.to change(Video, :count).by(-2)
        .and change(RejectedVideoImport, :count).by(2)

      expect(Video.where(id: video_keep.id)).to exist
      expect(RejectedVideoImport.where(channel: channel,
                                       youtube_video_id: %w[rej1AAAAAAA rej2AAAAAAA]).count).to eq(2)
    end

    it "redirects to /videos with a flash on HTML success" do
      patch imports_channel_path(completed_job), params: { keep_video_ids: [ video_keep.id ] }
      expect(response).to redirect_to(videos_path)
      follow_redirect!
      expect(flash[:notice]).to include("kept 1, rejected 2")
    end

    it "is a no-op when all videos are kept" do
      expect {
        patch imports_channel_path(completed_job),
              params: { keep_video_ids: [ video_keep.id, video_reject1.id, video_reject2.id ] }
      }.to change(Video, :count).by(0)
        .and change(RejectedVideoImport, :count).by(0)
    end

    it "destroys all when no keep_video_ids is sent" do
      expect {
        patch imports_channel_path(completed_job)
      }.to change(Video, :count).by(-3)
        .and change(RejectedVideoImport, :count).by(3)
    end

    it "is idempotent on repeat submit (candidate set empty)" do
      patch imports_channel_path(completed_job), params: { keep_video_ids: [] }
      expect {
        patch imports_channel_path(completed_job), params: { keep_video_ids: [] }
      }.to change(RejectedVideoImport, :count).by(0)
      expect(response).to redirect_to(videos_path)
    end

    it "rejects PATCH against a still-running ImportJob" do
      running = ImportJob.create!(channel: channel, enqueued_by: user, status: :running)
      patch imports_channel_path(running), params: { keep_video_ids: [] }
      expect(response).to have_http_status(:found)
    end

    it "returns JSON with kept/rejected counts" do
      patch imports_channel_path(completed_job),
            params: { keep_video_ids: [ video_keep.id ] },
            headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["kept"]).to eq(1)
      expect(body["rejected"]).to eq(2)
      expect(body["import_job"]["status"]).to eq("completed")
    end
  end
end
