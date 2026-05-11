# Phase 25 — 01a. One row in the attempt log table. Reused by:
#
#   - `/settings/security/attempts` index table
#   - `/settings/security/attempts/:id` show page (rendered as a
#     single-row table for visual symmetry)
#   - (later) the pending-approval notification card in 01b / 01c
#
# Single-purpose presenter: takes one `LoginAttempt`, renders the
# columns the table shows. Helpers live in `LoginAttemptsHelper` —
# this component delegates wholesale to keep one source of truth.
class LoginAttemptRowComponent < ViewComponent::Base
  include LoginAttemptsHelper

  def initialize(attempt:, show_detail_link: true)
    @attempt = attempt
    @show_detail_link = show_detail_link
  end

  attr_reader :attempt

  def show_detail_link?
    @show_detail_link
  end

  def result_label
    login_attempt_result_label(attempt)
  end

  def result_css
    login_attempt_result_css(attempt)
  end

  def reason_label
    login_attempt_reason_label(attempt)
  end

  def geo_label
    login_attempt_geo_label(attempt)
  end
end
