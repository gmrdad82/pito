# Pito TUI screen export
#
# Emits per-panel TOML specs that the Rust `pito` TUI client compiles in
# via `include_str!` + `serde`-deserialized `PanelSpec` structs.
#
# ## Inputs
#
# - Panel VC class definitions + class-level docblock headers (kwargs,
#   focusables, CABLE_CHANNEL, keybinds, sub-panel composition)
# - `Pito::Theme::Sections` tokens (screen→accent map + recipes)
# - `config/locales/**.yml` (all user-visible strings)
# - `docs/design.md` locks (terminology, brand caps, mode model)
# - `config/keybindings.yml` (key labels)
#
# ## Outputs
#
# `extras/cli/src/screens/specs/<screen>/<panel>.toml` — one TOML file
# per Panel VC. The Rust client `include_str!`s these.
#
# ## Status
#
# Skeleton — implementation pending TUI work. Currently emits the
# panel inventory without populating each TOML body.
#
# ## Usage
#
# bin/rails pito:tui:export                # emit all panels
# bin/rails pito:tui:export[screen=home]   # one screen
# bin/rails pito:tui:export[panel=Pito::SecurityPanelComponent]  # one panel

namespace :pito do
  namespace :tui do
    desc "Emit per-panel TOML specs for the Rust TUI client (extras/cli/)"
    task export: :environment do
      raise NotImplementedError, <<~MSG
        Pito::TUI screen export pending implementation.

        Plan: walk every Panel ViewComponent class
        (Pito::*PanelComponent + Screen::Videos::*PanelComponent +
        Screen::Games::*PanelComponent), parse class-level docblock
        for kwargs / focusables / CABLE_CHANNEL / keybinds, emit per-
        panel TOML at extras/cli/src/screens/specs/<screen>/<panel>.toml.

        See docs/tui.md § Screen export for the full contract.
      MSG
    end
  end
end
