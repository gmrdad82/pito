namespace :pito do
  namespace :transitions do
    desc "export Pito::Transitions::Tokens to CSS custom properties + Rust constants"
    task export: :environment do
      Pito::Transitions::Exporter.export_css!
      Pito::Transitions::Exporter.export_rust!
      puts "exported transitions tokens → _theme.css + extras/cli/src/transitions.rs"
    end
  end
end
