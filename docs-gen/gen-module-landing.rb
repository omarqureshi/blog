#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Per-module class listing -> <out>/AWSCDK/<Module>/index.html
# Groups the module's types into Classes / Interfaces / Enums sections, each sorted
# alphabetically. Names + links come from the YARD output (authoritative Ruby names);
# kind + one-line summary from the jsii assembly.
#
#   gen-module-landing.rb <assembly.jsii(.gz)> <out-dir>
require 'json'
require 'zlib'

assembly_path, out_dir = ARGV
awscdk = File.join(out_dir, 'AWSCDK')
raw = File.binread(assembly_path)
assembly = JSON.parse(raw[0, 2].bytes == [0x1f, 0x8b] ? Zlib.gunzip(raw) : raw)

subs = assembly.fetch('submodules', {})
norm = ->(s) { s.downcase.gsub(/[^a-z0-9]/, '') }

ruby_mod = {}
subs.each { |fqn, s| (rm = s.dig('targets', 'ruby', 'module')) && (ruby_mod[fqn] = rm) }

# Ruby module -> { normalized class name -> {kind, summary} }
by_mod = Hash.new { |h, k| h[k] = {} }
assembly.fetch('types', {}).each do |fqn, t|
  rm = ruby_mod[fqn.rpartition('.').first]
  next unless rm

  by_mod[rm][norm.call(fqn.rpartition('.').last)] = { kind: t['kind'], summary: t.dig('docs', 'summary') }
end

esc = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
SECTIONS = [['class', 'Classes'], ['interface', 'Interfaces'], ['enum', 'Enums']].freeze

STYLE = <<~CSS
  :root{color-scheme:light dark;--bg:#fbfbfc;--ink:#1a1a1e;--muted:#70707a;--line:#e6e6ea;--accent:#cc342d}
  @media(prefers-color-scheme:dark){:root{--bg:#131317;--ink:#e9e9ee;--muted:#9a9aa6;--line:#2a2a33}}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,sans-serif}
  .wrap{max-width:1120px;margin:0 auto;padding:2rem 1.25rem 4rem}
  .cdk-crumb{margin:0 0 .4rem;font:600 .85rem system-ui,-apple-system,sans-serif}
  .cdk-crumb a{color:var(--accent);text-decoration:none}
  .cdk-crumb a:hover{text-decoration:underline}
  .cdk-crumb .sep{color:var(--muted);margin:0 .45rem;font-weight:400}
  .cdk-crumb .cur{color:var(--muted);font-weight:400;font-family:ui-monospace,monospace}
  h1{font-size:1.7rem;margin:.4rem 0 .2rem;font-family:ui-monospace,monospace}
  p.sub{color:var(--muted);margin:.1rem 0 .5rem}
  h2.sec{font-size:.78rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);font-weight:700;margin:1.75rem 0 .35rem}
  h2.sec .ct{opacity:.6;font-weight:400;margin-left:.3rem}
  .row{display:flex;gap:.7rem;align-items:baseline;padding:.4rem .2rem;border-top:1px solid var(--line);text-decoration:none;color:inherit}
  .row:hover{background:color-mix(in srgb,var(--accent) 5%,transparent)}
  .n{font-family:ui-monospace,monospace;font-weight:600;flex:0 0 auto}
  .s{color:var(--muted);font-size:.88rem}
  footer{margin-top:1.75rem;color:var(--muted);font-size:.82rem;border-top:1px solid var(--line);padding-top:1rem;text-align:center}
CSS

render_rows = lambda do |items|
  items.sort_by { |c| c[:name].downcase }.map do |c|
    summary = c[:summary] ? %(<span class="s">#{esc.call(c[:summary][0, 90])}</span>) : ''
    %(<a class="row" href="#{c[:href]}"><span class="n">#{esc.call(c[:name])}</span>#{summary}</a>)
  end.join("\n      ")
end

count = 0
(File.directory?(awscdk) ? Dir.children(awscdk) : []).each do |d|
  dir = File.join(awscdk, d)
  next unless File.directory?(dir)

  rm = "AWSCDK::#{d}"
  info = by_mod[rm]
  types = Dir.glob(File.join(dir, '*.html')).filter_map do |f|
    base = File.basename(f)
    next if base == 'index.html'

    name = File.basename(f, '.html')
    meta = info[norm.call(name)] || {}
    { name: name, href: base, kind: meta[:kind], summary: meta[:summary] }
  end
  next if types.empty?

  by_kind = types.group_by { |c| c[:kind] }
  sections = SECTIONS.filter_map do |kind, label|
    items = by_kind[kind]
    next if items.nil? || items.empty?

    %(<h2 class="sec">#{label} <span class="ct">#{items.length}</span></h2>\n      #{render_rows.call(items)})
  end
  other = types.reject { |c| SECTIONS.map(&:first).include?(c[:kind]) }
  sections << %(<h2 class="sec">Other <span class="ct">#{other.length}</span></h2>\n      #{render_rows.call(other)}) if other.any?

  File.write(File.join(dir, 'index.html'), <<~HTML)
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{esc.call(rm)} — AWS CDK for Ruby</title>
    <style>#{STYLE}</style></head><body><div class="wrap">
      <nav class="cdk-crumb"><a href="../index.html">AWSCDK</a><span class="sep">/</span><span class="cur">#{esc.call(d)}</span></nav>
      <h1>#{esc.call(rm)}</h1>
      <p class="sub">#{types.length} types</p>
      #{sections.join("\n      ")}
      <footer>Generated on #{Time.now.strftime('%a %b %d %H:%M:%S %Y')}.</footer>
    </div></body></html>
  HTML
  count += 1
end
puts "wrote #{count} module landings (grouped by kind)"
