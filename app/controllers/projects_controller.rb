# Phase 4 §6 / §9.1 — Project Workspace controller.
#
# Default-create instant-new (§2 "Default-create everywhere"): the create
# action takes no params, instantiates a Project with the model-level default
# `name = "Untitled project"` and redirects to the show page where the user
# renames inline.
#
# Show renders three fixed panes (Footage / Notes / Timelines, §9.1).
#
# Destructive actions route through the existing /deletions/:type/:ids
# framework — there is no inline delete button on this controller.
class ProjectsController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Phase 4 Wave 2 — sortable `/projects` index. URL params drive the order
  # so the view stays bookmarkable / shareable, mirroring `ChannelsController`.
  #
  # Wave 3.5+ aggregates revamp (2026-05-06): the index footage / notes
  # columns now sort by the cached aggregate values
  # (`footage_duration_seconds`, `notes_words_total`) rather than the raw
  # row counts. The counter caches stay on the model for the show-page
  # `(N)` headings and any future use; they're just no longer wired into
  # this allowlist.
  ALLOWED_SORTS = {
    "name" => "projects.name",
    "created_at" => "projects.created_at",
    "footage_duration_seconds" => "projects.footage_duration_seconds",
    "notes_words_total" => "projects.notes_words_total",
    "timelines_count" => "projects.timelines_count"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  # Wave 2 — footage table sort. Allowlist of sortable column names mapped
  # to their qualified DB expressions. `local_path` is the implicit
  # alphabetical default (matches the importer's lexicographic file walk).
  # Sorting by `game` joins the games table once via the optional belongs_to.
  FOOTAGE_SORT_COLUMNS = {
    "filename"         => "footages.filename",
    "game"             => "games.title",
    "resolution"       => "footages.resolution",
    "fps"              => "footages.fps",
    "bit_depth"        => "footages.bit_depth",
    "duration_seconds" => "footages.duration_seconds",
    "filesize_bytes"   => "footages.filesize_bytes",
    "source"           => "footages.source",
    "local_path"       => "footages.local_path"
  }.freeze
  FOOTAGE_DEFAULT_SORT = "local_path".freeze
  FOOTAGE_DEFAULT_DIR  = "asc".freeze

  # Wave 2 — footage table filter dimensions. Each maps a URL param name
  # to the column it filters on. Chips render only when the project's
  # footage has > 1 distinct value for the dimension.
  FOOTAGE_FILTER_DIMENSIONS = %i[game fps resolution bit_depth source].freeze

  # Notes table sort. Lives alongside the footage table on the same
  # show page, so URL params are namespaced (`notes_sort` / `notes_dir`)
  # to keep each table's URL state independent. `last_modified` is the
  # default — most-recently-modified first matches the legacy ordering.
  NOTES_SORT_COLUMNS = {
    "title"         => "notes.title",
    "words"         => "notes.words_count",
    "last_modified" => "notes.last_modified_at"
  }.freeze
  NOTES_DEFAULT_SORT = "last_modified".freeze
  NOTES_DEFAULT_DIR  = "desc".freeze

  def index
    @projects = Project.order(sort_clause)
    @sort = sanitized_sort_key
    @dir = sanitized_dir
  end

  def show
    @project = Project.find(params[:id])
    @notes_sort = sanitized_notes_sort_key
    @notes_dir  = sanitized_notes_dir
    @notes = @project.notes.order(notes_order_clause)
    @timelines = @project.timelines.order(created_at: :desc)
    @notes_locked = NotesLockGuard.locked?

    # Filter chip options come from the *unfiltered* set so a narrowed
    # view still shows every distinct value the user can pivot to. Chips
    # only render when the project's footage has > 1 distinct value
    # (suppresses chip groups on uniform data — see spec).
    all_footages = @project.footages
    @footage_filter_options = footage_filter_options_for(all_footages)

    # Filter + sort applied here. The unfiltered scope above is reused
    # so ordering joins (e.g. games for the `game` sort) and the
    # SELECT happen once per request.
    @footage_active_filters = active_footage_filters
    @footage_sort = sanitized_footage_sort_key
    @footage_dir  = sanitized_footage_dir
    @footages = ordered_footages(filtered_footages(all_footages))
  end

  def edit
    @project = Project.find(params[:id])
  end

  def create
    project = Project.new
    project.save!
    redirect_to project_path(project), notice: "project created."
  end

  def update
    @project = Project.find(params[:id])
    if @project.update(update_params)
      redirect_to project_path(@project), notice: "project updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    project = Project.find(params[:id])
    project.destroy!
    redirect_to projects_path, notice: "project deleted."
  end

  private

  def update_params
    params.require(:project).permit(:name)
  end

  def sanitized_sort_key
    ALLOWED_SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  def sanitized_dir
    requested = params[:dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : DEFAULT_DIR
  end

  def sort_clause
    # Both fragments are derived from frozen allowlists (ALLOWED_SORTS /
    # ALLOWED_DIRS); they never contain user input. The local-variable
    # binding mirrors `ChannelsController#sort_clause` so Brakeman's SQL
    # check resolves the literals through the allowlist constants.
    column = ALLOWED_SORTS[params[:sort]] || ALLOWED_SORTS[DEFAULT_SORT]
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : DEFAULT_DIR
    Arel.sql("#{column} #{direction}")
  end

  # ---- Wave 2 footage table helpers --------------------------------------

  def sanitized_footage_sort_key
    FOOTAGE_SORT_COLUMNS.key?(params[:sort]) ? params[:sort] : FOOTAGE_DEFAULT_SORT
  end

  def sanitized_footage_dir
    requested = params[:dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : FOOTAGE_DEFAULT_DIR
  end

  # Builds the `{dimension => [{value:, label:}, ...]}` hash the view uses
  # to render filter chips. Each list is sorted naturally for the type:
  # numeric for fps / bit_depth, alphabetical for strings, by title for
  # games. Returns an empty list for any dimension with ≤ 1 distinct
  # value (chip group is then suppressed in the view).
  def footage_filter_options_for(scope)
    options = {}

    # game — distinct game_ids on the project's footage. We pull the games
    # in a single query and project to {id, title}; rows with no game
    # contribute a NULL we drop (the chip group is "filter to a known
    # game").
    game_ids = scope.where.not(game_id: nil).distinct.pluck(:game_id)
    games = Game.where(id: game_ids).order(:title).pluck(:id, :title)
    options[:game] = games.size > 1 ? games.map { |id, title| { value: id.to_s, label: title } } : []

    # fps — decimal column. Render with `.to_f` so 60.000 → 60.0 (matches
    # the cell display below). Drop nulls.
    fps_values = scope.where.not(fps: nil).distinct.pluck(:fps).compact.sort
    options[:fps] = fps_values.size > 1 ? fps_values.map { |v| { value: v.to_f.to_s, label: v.to_f.to_s } } : []

    # resolution — string. Sorted alphabetically so chips read in a
    # stable order.
    resolutions = scope.where.not(resolution: nil).distinct.pluck(:resolution).compact.sort
    options[:resolution] = resolutions.size > 1 ? resolutions.map { |r| { value: r, label: r } } : []

    # bit_depth — integer. Always ascending (8 → 10 → 12).
    bit_depths = scope.where.not(bit_depth: nil).distinct.pluck(:bit_depth).compact.sort
    options[:bit_depth] = bit_depths.size > 1 ? bit_depths.map { |b| { value: b.to_s, label: "#{b}-bit" } } : []

    # source — enum, surfaced as the string accessor (`obs` / `camera`).
    # The chip label uses `FootageHelper#human_source` so the user-facing
    # text matches the table column (`OBS` / `Camera`); the URL value
    # stays the raw enum string so filter URLs remain canonical.
    sources = scope.distinct.pluck(:source).compact.sort
    # `source` is an enum integer column; `pluck(:source)` returns the
    # mapped string thanks to ActiveRecord's enum decoding. Stable sort.
    options[:source] = sources.size > 1 ? sources.map { |s| { value: s, label: helpers.human_source(s) } } : []

    options
  end

  def filtered_footages(scope)
    if params[:game].present?
      scope = scope.where(game_id: params[:game])
    end
    if params[:fps].present?
      # Decimal compare — coerce to BigDecimal so `60.0` matches `60.000`.
      scope = scope.where(fps: BigDecimal(params[:fps].to_s))
    end
    if params[:resolution].present?
      scope = scope.where(resolution: params[:resolution])
    end
    if params[:bit_depth].present?
      scope = scope.where(bit_depth: params[:bit_depth].to_i)
    end
    if params[:source].present? && Footage.sources.key?(params[:source])
      scope = scope.where(source: params[:source])
    end
    scope
  rescue ArgumentError
    # BigDecimal raises on garbage like `?fps=oops`. Treat as no filter.
    scope
  end

  def ordered_footages(scope)
    column = FOOTAGE_SORT_COLUMNS.fetch(sanitized_footage_sort_key)
    # Inline-ternary sanitization (mirror of `ChannelsController#sort_clause`)
    # — brakeman's flow analysis trusts this shape; an extracted method
    # produces a false-positive SQL-injection warning even though the same
    # logic runs.
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : FOOTAGE_DEFAULT_DIR

    # `game` sort needs the games table joined. `left_joins` keeps rows
    # without a game in the result set; nulls trail naturally per
    # PostgreSQL's default `NULLS LAST` for ASC and `NULLS FIRST` for
    # DESC — acceptable here (no project has so many footages that
    # null placement is a usability issue).
    scope = scope.left_joins(:game) if sanitized_footage_sort_key == "game"
    scope.order(Arel.sql("#{column} #{direction}"))
  end

  def active_footage_filters
    FOOTAGE_FILTER_DIMENSIONS.select { |k| params[k].present? }
  end

  # ---- Notes table helpers ----------------------------------------------

  def sanitized_notes_sort_key
    NOTES_SORT_COLUMNS.key?(params[:notes_sort]) ? params[:notes_sort] : NOTES_DEFAULT_SORT
  end

  def sanitized_notes_dir
    requested = params[:notes_dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : NOTES_DEFAULT_DIR
  end

  def notes_order_clause
    # Both fragments derive from frozen allowlists (NOTES_SORT_COLUMNS,
    # ALLOWED_DIRS) and never contain user input. The inline-ternary
    # shape mirrors `ChannelsController#sort_clause` so Brakeman's flow
    # analysis trusts the literals through the allowlist.
    column = NOTES_SORT_COLUMNS[params[:notes_sort]] || NOTES_SORT_COLUMNS[NOTES_DEFAULT_SORT]
    direction = ALLOWED_DIRS.include?(params[:notes_dir]&.downcase) ? params[:notes_dir].downcase : NOTES_DEFAULT_DIR
    Arel.sql("#{column} #{direction}")
  end
end
