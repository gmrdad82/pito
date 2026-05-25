# pito:test:sessions — dev/test rake surface for the security panel's
# sessions table.
#
# Purpose:
#   Seed N fake Session rows for the first User and broadcast each one via
#   `Pito::CableBroadcaster` on `pito:home:security` with the same payload
#   shape the `Session#after_create` callback (C9) uses. The ~500 ms cadence
#   between inserts lets you watch the scramble animation fire per row in the
#   live UI without a page reload.
#
#   A paired `reset` task destroys all non-active-user sessions so test clutter
#   is easy to clear. Together the two tasks satisfy the CLAUDE.md rule:
#   "every pito:test:* requires a clear/reset option per category".
#
# Tasks:
#   bin/rails pito:test:sessions:seed    # create N sessions + broadcast each
#   bin/rails pito:test:sessions:reset   # destroy non-current sessions
#
# Env vars (both tasks):
#   COUNT=N     override the number of sessions to seed (default: 5)
#   DELAY=ms    override the cadence between inserts in milliseconds (default: 500)
#
# Dependencies:
#   - User (at least one row must exist)
#   - Session (model + migration present)
#   - Pito::CableBroadcaster (ActionCable + Redis must be reachable for
#     broadcasts to land; the task continues even if Redis is down — the
#     Session row is persisted regardless)
#   - Pito::Formatter::UserAgent (used by Session#before_validation to
#     project device + browser from the synthetic UA string)
#
# Identification convention:
#   Every session seeded by this task carries a `user_agent` that starts with
#   "pito:test:sessions:" so `reset` can identify and destroy exactly those
#   rows without touching real or other test-seeded sessions.

namespace :pito do
  namespace :test do
    namespace :sessions do
      SESSIONS_PANEL_CHANNEL    = "pito:home:security".freeze
      SESSIONS_TEST_UA_PREFIX   = "pito:test:sessions:".freeze

      # Realistic-looking synthetic user agents. The UA strings are long enough
      # that `Pito::Formatter::UserAgent` resolves a real device + browser pair
      # from them, so the seeded rows display useful values in the sessions table.
      FAKE_USER_AGENTS = [
        # device: linux, browser: firefox
        "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0",
        # device: macos, browser: chrome
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        # device: windows, browser: edge
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
        # device: ios, browser: safari
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1",
        # device: android, browser: chrome
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
        # device: macos, browser: firefox
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:125.0) Gecko/20100101 Firefox/125.0",
        # device: windows, browser: chrome
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Safari/537.36",
        # device: linux, browser: chrome
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].freeze

      FAKE_IPS = %w[
        192.168.1.42
        10.0.0.7
        172.16.0.23
        203.0.113.55
        198.51.100.12
        192.168.0.101
        10.10.5.88
        185.220.101.34
      ].freeze

      desc "seed N fake Session rows + broadcast each on pito:home:security (COUNT=5 DELAY=500)"
      task seed: :environment do
        count = (ENV.fetch("COUNT", 5)).to_i
        delay = (ENV.fetch("DELAY", 500)).to_i.clamp(0, 30_000)

        user = User.order(:id).first
        if user.nil?
          abort "[pito:test:sessions:seed] no User present; seed a user first"
        end

        puts "[pito:test:sessions:seed] seeding #{count} session(s) for user=#{user.id} " \
             "delay=#{delay}ms channel=#{SESSIONS_PANEL_CHANNEL}"

        count.times do |i|
          ua_base   = FAKE_USER_AGENTS[i % FAKE_USER_AGENTS.length]
          ip        = FAKE_IPS[i % FAKE_IPS.length]

          # Prepend the test-seed prefix so `reset` can find these rows,
          # but keep the real UA body so `Pito::Formatter::UserAgent` still
          # resolves a meaningful device + browser pair for the table.
          synthetic_ua = "#{SESSIONS_TEST_UA_PREFIX}#{ua_base}"

          session, _plaintext = Session.create_for!(
            user: user,
            ip: ip,
            user_agent: synthetic_ua
          )

          Pito::CableBroadcaster.broadcast_panel(
            SESSIONS_PANEL_CHANNEL,
            kind: "session_created",
            payload: {
              session_id: session.id,
              device:     session.device.to_s,
              browser:    session.browser.to_s,
              ip:         ip,
              user_agent: ua_base,
              created_at: session.created_at.iso8601
            }
          )

          puts "[pito:test:sessions:seed] #{i + 1}/#{count} id=#{session.id} " \
               "device=#{session.device} browser=#{session.browser} ip=#{ip}"

          sleep(delay / 1000.0) if delay.positive? && i < count - 1
        end

        puts "[pito:test:sessions:seed] done — #{count} session(s) created"
      end

      desc "destroy all non-current-user sessions seeded by pito:test:sessions:seed"
      task reset: :environment do
        destroyed = Session
          .where("user_agent LIKE ?", "#{SESSIONS_TEST_UA_PREFIX}%")
          .delete_all

        puts "[pito:test:sessions:reset] deleted #{destroyed} test-seeded session(s)"
      end
    end
  end
end
