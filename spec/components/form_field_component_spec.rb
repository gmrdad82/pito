require "rails_helper"

RSpec.describe FormFieldComponent, type: :component do
  let(:video) { Video.new(title: "") }
  let(:template) { ActionView::Base.empty }

  def build_form(model)
    ActionView::Helpers::FormBuilder.new(model.model_name.param_key, model, template, {})
  end

  it "renders a text field with label" do
    form = build_form(Video.new)
    render_inline(described_class.new(form: form, field: :title))
    expect(page).to have_css("label", text: "title")
    expect(page).to have_css("input[type='text']")
  end

  it "renders a text area" do
    form = build_form(Video.new)
    render_inline(described_class.new(form: form, field: :description, type: :text_area))
    expect(page).to have_css("label", text: "description")
    expect(page).to have_css("textarea")
  end

  it "renders a select" do
    form = build_form(Video.new)
    options = [ [ "public", "public_video" ] ]
    render_inline(described_class.new(form: form, field: :privacy_status, type: :select, options: options))
    expect(page).to have_css("select")
    expect(page).to have_css("option", text: "public")
  end

  it "shows error message and red border on invalid field" do
    video.validate
    form = build_form(video)
    render_inline(described_class.new(form: form, field: :title))
    expect(page).to have_css("span.text-danger", text: "can't be blank")
    expect(page).to have_css("input[style*='border-color']")
  end

  it "does not show error styling on valid field" do
    form = build_form(Video.new(title: "ok"))
    render_inline(described_class.new(form: form, field: :title))
    expect(page).to have_no_css("span.text-danger")
  end

  it "accepts custom label" do
    form = build_form(Video.new)
    render_inline(described_class.new(form: form, field: :channel_id, label: "channel"))
    expect(page).to have_css("label", text: "channel")
  end
end
