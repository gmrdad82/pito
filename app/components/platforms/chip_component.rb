class Platforms::ChipComponent < ViewComponent::Base
  SLUG_BRAND = {
    "ps"     => { label: "PS",     color: "#003791" },
    "switch" => { label: "Switch", color: "#E60012" },
    "steam"  => { label: "Steam",  color: "#00ADEE" }
  }.freeze

  # 2026-05-18 FN2 — canonical chip-slug → Platform-slug mapping. The
  # chip vocabulary (`ps` / `switch` / `steam`) collapses multiple
  # IGDB platforms into one user-facing surface; this map names the
  # SINGLE canonical platform row each chip resolves to when the
  # ownership-matrix controller flips `[owned]` / `[played]`.
  #
  # Canonical picks (user-confirmed 2026-05-18):
  #   - `ps`     → `ps5`     (NOT ps4; PS5 is the current canonical PS)
  #   - `switch` → `switch-2` (NOT switch; Switch 2 is the current
  #                           canonical Switch — DB slug includes the
  #                           hyphen because FriendlyId derives the slug
  #                           from the platform name "Nintendo Switch 2")
  #   - `steam`  → `steam`   (single PC umbrella per ADR 0013 collapse)
  #
  # Used by `Games::OwnershipTogglesController` (writes a
  # `game_platforms` join row with `source: "user"` when the user
  # marks a chip as owned but IGDB has not listed the platform) and
  # by `Game::OwnershipMatrixComponent` (reads ownership / played
  # state for the chip's canonical platform).
  CANONICAL_PLATFORM_SLUG_BY_CHIP = {
    "ps"     => "ps5",
    "switch" => "switch-2",
    "steam"  => "steam"
  }.freeze

  def initialize(slug:, size: :sm)
    @slug = slug.to_s
    @size = size  # :sm (tile footer, 12px), :md (detail page, 14px). Future: :lg.
  end

  def render?
    SLUG_BRAND.key?(@slug)
  end

  def label
    # I18n is the canonical label surface. SLUG_BRAND.dig(:label)
    # remains the fallback so direct constant readers
    # (Game::OwnershipMatrixComponent, OwnershipTogglesController,
    # Game::PlatformOwnershipChipComponent) keep working until they
    # route through this method.
    I18n.t("platforms.chip.label.#{@slug}", default: SLUG_BRAND.dig(@slug, :label))
  end

  def color
    SLUG_BRAND.dig(@slug, :color)
  end

  def size_class
    { sm: "platform-chip--sm", md: "platform-chip--md" }.fetch(@size)
  end
end
