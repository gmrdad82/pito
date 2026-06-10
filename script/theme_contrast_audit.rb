# frozen_string_literal: true

# Theme contrast audit (WCAG 2.x), scoped to ACTUAL token usage in the UI:
#   * Text:  fg_default / fg_dim / fg_faded  +  accent_yellow / accent_cyan /
#            accent_orange / accent_red / accent_green / accent_purple
#            (every accent EXCEPT blue, which is only brand_pito), evaluated against PAGE (bg_root) and SURFACE
#            (bg_surface) — the two backgrounds text sits on. Bar: AA 4.5:1
#            (fg_faded is a placeholder/disabled tone, judged at the 3:1 floor).
#   * brand_pito (#5170ff): NOT text — it is the ascii logo blocks (on the page)
#            and the chatbox / echo borderline. Non-text/UI bar: 3:1.
#
# Run: bundle exec rails runner script/theme_contrast_audit.rb
module ContrastAudit
  module_function

  def lin(chan)
    chan /= 255.0
    chan <= 0.03928 ? chan / 12.92 : ((chan + 0.055) / 1.055)**2.4
  end

  def lum(hex)
    h = hex.delete("#")
    r, g, b = [ h[0, 2], h[2, 2], h[4, 2] ].map { |x| x.to_i(16) }
    (0.2126 * lin(r)) + (0.7152 * lin(g)) + (0.0722 * lin(b))
  end

  def ratio(fg, bg)
    a = lum(fg)
    b = lum(bg)
    ([ a, b ].max + 0.05) / ([ a, b ].min + 0.05)
  end

  def mark(r)
    return "❌" if r < 3.0
    return "⚠️" if r < 4.5

    "✅"
  end

  TEXT = %i[fg_default fg_dim fg_faded
           accent_yellow accent_cyan accent_orange
           accent_red accent_green accent_purple].freeze
  PITO = "#5170ff"

  def run
    defs = Pito::Themes::Registry.all.sort_by { |d| [ d.mode == :light ? 0 : 1, d.slug ] }
    text_section(defs)
    pito_section(defs)
  end

  def text_section(defs)
    puts "## Text — fg trio + yellow/cyan/orange vs page & surface (AA 4.5:1)\n"
    puts "✅ ≥4.5 · ⚠️ 3–4.5 · ❌ <3.  `fg_faded` is a placeholder tone (3:1 floor).\n"
    %i[light dark].each do |mode|
      puts "\n### #{mode.to_s.upcase} themes\n"
      puts "| theme | fg | fg-dim | fg-faded | yellow | cyan | orange | red | green | purple | AA-fails/8 (surface) |"
      puts "|---|---|---|---|---|---|---|---|---|---|---:|"
      defs.select { |d| d.mode == mode }.each do |d|
        t = d.tokens
        cells = TEXT.map do |tok|
          rp = ratio(t[tok].to_s, t[:bg_root].to_s)
          rs = ratio(t[tok].to_s, t[:bg_surface].to_s)
          "p#{format('%.1f', rp)}#{mark(rp)} s#{format('%.1f', rs)}#{mark(rs)}"
        end
        bad = TEXT.reject { |x| x == :fg_faded }
                  .count { |tok| ratio(t[tok].to_s, t[:bg_surface].to_s) < 4.5 }
        puts "| **#{d.slug}** | #{cells.join(' | ')} | #{bad}/8 |"
      end
    end
  end

  def pito_section(defs)
    puts "\n## brand_pito #{PITO} — logo (on page) + chatbox/echo border (non-text, 3:1)\n"
    puts "| theme | mode | vs page | vs surface | verdict |"
    puts "|---|---|---:|---:|---|"
    defs.each do |d|
      t = d.tokens
      rp = ratio(PITO, t[:bg_root].to_s)
      rs = ratio(PITO, t[:bg_surface].to_s)
      v = [ rp, rs ].min >= 3.0 ? "OK" : "faint border on surface (#{format('%.1f', rs)})"
      puts "| #{d.slug} | #{d.mode} | #{format('%.2f', rp)} | #{format('%.2f', rs)} | #{v} |"
    end
  end
end

ContrastAudit.run
