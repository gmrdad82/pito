# Phase 12 — Step A (6a-sessions-and-login-ui.md). Cookie-session
# helpers for request and system specs.
#
# Phase 8 — tenant drop. The earlier `Current.tenant` pin is gone; the
# helper now mints a User row directly when a spec needs an
# already-signed-in caller.
#
# `sign_in_as(user)` mints a Session row and sets the `pito_session`
# signed cookie. Because Rails' integration test cookie jar lacks a
# `signed` accessor, we construct a minimal `ActionDispatch::Cookies::CookieJar`
# off the application's key generator, sign the cookie there, and copy
# the resulting opaque string into the integration cookie jar.
#
# Used by request specs that aren't testing `/login` itself.
module SignInHelpers
  def sign_in_as(user, remember: false)
    record, plaintext = Session.create_for!(
      user: user,
      ip: "127.0.0.1",
      user_agent: "RspecAgent",
      remember: remember
    )

    if respond_to?(:cookies) && defined?(integration_session)
      cookies[Sessions::Authenticator::COOKIE_NAME] = signed_cookie_value(plaintext)
    end

    record
  end

  private

  # Build a minimal ActionDispatch CookieJar bound to the application's
  # key generator, sign one cookie, and return the resulting opaque
  # string. The integration test jar then carries that string forward
  # into the next request, where Rails' standard request-time signed
  # cookie reader unwraps it. This is the same trick `request.cookie_jar.signed`
  # uses inside controllers.
  def signed_cookie_value(plaintext)
    request = ActionDispatch::TestRequest.create
    jar = ActionDispatch::Cookies::CookieJar.build(request, {})
    jar.signed[Sessions::Authenticator::COOKIE_NAME] = plaintext
    jar[Sessions::Authenticator::COOKIE_NAME.to_s]
  end
end

RSpec.configure do |config|
  config.include SignInHelpers, type: :request
  config.include SignInHelpers, type: :system
  config.include SignInHelpers, type: :feature

  # Phase 12 — Step A. Existing HTML-request specs were written before
  # cookie-session auth gated every controller action. Default every
  # request spec to "already signed in as a freshly minted user" so
  # those specs continue to test what they were written to test
  # (controller behavior, not the auth boundary). Specs that need to
  # assert on the /login redirect or on an unauthenticated state set
  # `metadata[:unauthenticated]` to `true`.
  config.before(:each, type: :request) do |example|
    next if example.metadata[:unauthenticated]

    user = User.first || FactoryBot.create(:user)
    sign_in_as(user)
  end

  # System specs use Capybara. The default rack_test driver shares the
  # signed-cookie machinery with the application via
  # `Capybara.current_session.driver.browser`. Mint a session row, sign
  # the cookie, and inject it into the Capybara cookie jar. Specs that
  # need to assert on /login bounce or test auth itself set
  # `metadata[:unauthenticated] => true`.
  config.before(:each, type: :system) do |example|
    next if example.metadata[:unauthenticated]

    user = User.first || FactoryBot.create(:user)

    record, plaintext = Session.create_for!(
      user: user,
      ip: "127.0.0.1",
      user_agent: "RspecSystem",
      remember: false
    )

    seed_request = ActionDispatch::TestRequest.create
    jar = ActionDispatch::Cookies::CookieJar.build(seed_request, {})
    jar.signed[Sessions::Authenticator::COOKIE_NAME] = plaintext
    raw = jar[Sessions::Authenticator::COOKIE_NAME.to_s]

    Capybara.current_session.driver.browser.set_cookie(
      "#{Sessions::Authenticator::COOKIE_NAME}=#{raw}; path=/"
    ) if Capybara.current_session.driver.respond_to?(:browser) &&
         Capybara.current_session.driver.browser.respond_to?(:set_cookie)

    @auto_signed_in_session = record
    @auto_signed_in_user    = user
  end
end
