require "rails_helper"

# Phase 7 Path A2 (literal full retract). Video no longer carries
# title/description/etc., so this spec uses Project (which has
# `name`) as the host model — Project's name is a presence-validated
# string, mirroring what Video's title used to provide for these
# component smokes.
RSpec.describe FormFieldComponent, type: :component do
  let(:project) { Project.new(name: "") }
  let(:template) { ActionView::Base.empty }

  def build_form(model)
    ActionView::Helpers::FormBuilder.new(model.model_name.param_key, model, template, {})
  end

  it "renders a text field with label" do
    form = build_form(Project.new)
    render_inline(described_class.new(form: form, field: :name))
    expect(page).to have_css("label", text: "name")
    expect(page).to have_css("input[type='text']")
  end

  it "renders a text area" do
    form = build_form(Note.new)
    render_inline(described_class.new(form: form, field: :title, type: :text_area))
    expect(page).to have_css("label", text: "title")
    expect(page).to have_css("textarea")
  end

  it "renders a select" do
    form = build_form(Note.new)
    options = [ [ "draft", "draft" ] ]
    render_inline(described_class.new(form: form, field: :title, type: :select, options: options))
    expect(page).to have_css("select")
    expect(page).to have_css("option", text: "draft")
  end

  it "shows error message and red border on invalid field" do
    project.validate
    form = build_form(project)
    render_inline(described_class.new(form: form, field: :name))
    expect(page).to have_css("span.text-danger", text: "can't be blank")
    expect(page).to have_css("input[style*='border-color']")
  end

  it "does not show error styling on valid field" do
    form = build_form(Project.new(name: "ok"))
    render_inline(described_class.new(form: form, field: :name))
    expect(page).to have_no_css("span.text-danger")
  end

  it "accepts custom label" do
    form = build_form(Project.new)
    render_inline(described_class.new(form: form, field: :name, label: "project"))
    expect(page).to have_css("label", text: "project")
  end
end
