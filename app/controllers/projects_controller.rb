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

  def index
    @projects = Project.order(created_at: :desc)
  end

  def show
    @project = Project.find(params[:id])
    @footages = @project.footages.order(recorded_at: :desc, created_at: :desc)
    @notes = @project.notes.order(last_modified_at: :desc)
    @timelines = @project.timelines.order(created_at: :desc)
    @notes_locked = NotesLockGuard.locked?(@project.tenant)
  end

  def create
    project = Project.new(tenant: default_tenant)
    project.save!
    redirect_to project_path(project), notice: "project created."
  end

  def update
    @project = Project.find(params[:id])
    if @project.update(update_params)
      redirect_to project_path(@project), notice: "project updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    project = Project.find(params[:id])
    project.destroy!
    redirect_to projects_path, notice: "project deleted."
  end

  private

  def update_params
    params.require(:project).permit(:name, :concept)
  end

  def default_tenant
    Tenant.order(:id).first || Tenant.create!(name: "Primary")
  end
end
