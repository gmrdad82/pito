# frozen_string_literal: true

namespace :pito do
  namespace :themes do
    desc "Generate themes.css from the theme registry and write it to app/assets/tailwind/themes.css"
    task export: :environment do
      output_path = Rails.root.join("app/assets/tailwind/themes.css")
      css = Pito::Themes::CssGenerator.call
      File.write(output_path, css)
      puts "Written #{output_path} (#{css.bytesize} bytes, #{Pito::Themes::Registry.all.length} themes)"
    end
  end
end
