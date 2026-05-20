class BracketedLinkComponent < ViewComponent::Base
  # Phase 7.5 — Step 01 hygiene sweep dropped the deprecated `confirm:`
  # kwarg. The project rule forbids `window.confirm` / `data-turbo-confirm`;
  # destructive flows go through either the action confirmation page
  # framework (/deletions, /syncs) or an in-page modal via
  # ConfirmModalComponent + modal-trigger controller.
  #
  # 2026-05-16 polish — external-link auto-detection. When `href:` is an
  # absolute `http://` or `https://` URL, the component automatically
  # applies `target="_blank"` plus `rel="noopener noreferrer"` so callers
  # never forget the hard-rule pairing (see `docs/design.md` → "External
  # links — new tab convention" and the matching `decorate_external_links`
  # post-pass on `render_markdown`). Relative paths (`/channels/1`, `#tag`,
  # `mailto:`, `tel:`) stay default — internal Turbo navigation, back-button
  # history, and same-tab continuity keep working.
  #
  # Explicit caller-passed `target:` / `rel:` win — auto-detection is the
  # default for the unspecified case, never an overwrite. The sentinel for
  # "unspecified" is `:auto` so a caller can still pass `target: nil` to
  # force no attribute on an external URL (rare, but legal).
  # `as: :submit` switches the rendered tag from `<a>` to
  # `<button type="submit">` so the same bracketed-action chrome can be
  # used as a form submit (notifications webhook [update] buttons). The
  # CSS rule `button.bracketed` resets browser button chrome and pins
  # the bracketed-link family — see `application.css` near the
  # `button.bracketed.action-screen-submit` block.
  def initialize(label:, href: nil, destructive: false, method: nil, data: {}, active: false, target: :auto, rel: :auto, as: :link)
    @label = label
    @href = href
    @destructive = destructive
    @method = method
    @data = data
    @active = active
    @target = target
    @rel = rel
    @as = as
  end

  def active?
    @active || (@as == :link && @href.nil?)
  end

  def submit?
    @as == :submit
  end

  def css_classes
    classes = [ "bracketed" ]
    classes << "text-danger" if @destructive
    classes.join(" ")
  end

  def html_data
    attrs = @data.dup
    attrs[:turbo_method] = @method if @method
    attrs
  end

  # Resolved `target` attribute. Caller's explicit value wins; otherwise
  # auto-detect from the href. `nil` (the rendered default) means no
  # attribute is emitted.
  def resolved_target
    return @target unless @target == :auto

    external_href? ? "_blank" : nil
  end

  # Resolved `rel` attribute. Same precedence rule as `resolved_target`.
  # The auto path emits the canonical `noopener noreferrer` pairing — the
  # one mandated by `docs/design.md`. `nil` means no attribute.
  def resolved_rel
    return @rel unless @rel == :auto

    external_href? ? "noopener noreferrer" : nil
  end

  private

  # An href is external when it is an absolute `http://` or `https://`
  # URL. Relative paths, fragment anchors, `mailto:`, `tel:`, and any
  # other scheme are treated as internal — same heuristic as
  # `ApplicationHelper#decorate_external_links` so the component and the
  # markdown post-pass agree on what "external" means.
  def external_href?
    @href.to_s.match?(/\Ahttps?:\/\//i)
  end
end
