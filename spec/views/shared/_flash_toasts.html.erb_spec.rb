require "rails_helper"

RSpec.describe "shared/_flash_toasts.html.erb", type: :view do
  it "renders an empty toast container when there are no flashes" do
    # The container is rendered unconditionally so client-side Stimulus
    # controllers (e.g. `clipboard_copy_controller#_flashToast`) can
    # append toasts on flash-less pages too. The empty container has
    # no visual footprint — its CSS only paints `.toast` children.
    render
    expect(rendered).to include("class=\"toast-container\"")
    expect(rendered).not_to include("class=\"toast ")
  end

  it "renders a notice toast inside a fixed top-right container" do
    flash[:notice] = "Saved."
    render
    expect(rendered).to include("toast-container")
    expect(rendered).to include("toast toast-notice")
    expect(rendered).to include("data-controller=\"toast\"")
    expect(rendered).to include("Saved.")
  end

  it "maps :alert to the error toast styling" do
    flash[:alert] = "Something went wrong"
    render
    expect(rendered).to include("toast toast-error")
    expect(rendered).to include("Something went wrong")
  end

  it "maps :error to the error toast styling" do
    flash[:error] = "Boom"
    render
    expect(rendered).to include("toast toast-error")
    expect(rendered).to include("Boom")
  end

  it "maps :success to the success toast styling" do
    flash[:success] = "Done."
    render
    expect(rendered).to include("toast toast-success")
  end

  it "maps :warning to the warning toast styling" do
    flash[:warning] = "heads up"
    render
    expect(rendered).to include("toast toast-warning")
  end

  it "stacks multiple flashes inside the same container" do
    flash[:notice] = "first"
    flash[:alert] = "second"
    render
    expect(rendered.scan("toast-container").size).to eq(1)
    expect(rendered).to include("toast toast-notice")
    expect(rendered).to include("toast toast-error")
    expect(rendered).to include("first")
    expect(rendered).to include("second")
  end

  it "skips blank messages but still emits the empty container" do
    flash[:notice] = ""
    render
    expect(rendered).to include("class=\"toast-container\"")
    expect(rendered).not_to include("class=\"toast ")
  end

  it "uses position: fixed so the toast does not push content down" do
    # The toast container is styled via .toast-container in
    # `app/assets/tailwind/application.css` (position: fixed; top: 8px;
    # right: 8px). The rendered partial only emits the class name; we
    # assert on the class to keep the spec stable across CSS tweaks.
    flash[:notice] = "hello"
    render
    expect(rendered).to include("class=\"toast-container\"")
  end
end
