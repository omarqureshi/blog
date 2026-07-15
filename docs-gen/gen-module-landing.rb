#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Per-namespace landing pages -> <out>/AWSCDK/<Module>[/<Sub>...]/index.html
# Every jsii submodule gets a landing: a top-level module (AWSCDK::S3) and any nested
# namespace (AWSCDK::ECR::Mixins). Each lists its classes/interfaces/enums (grouped,
# alphabetical) plus a "Namespaces" section linking to its child namespaces. Names +
# links come from the YARD output; kind + one-line summary from the jsii assembly.
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

# Ruby module -> { normalized type name -> {kind, summary} }
by_mod = Hash.new { |h, k| h[k] = {} }
assembly.fetch('types', {}).each do |fqn, t|
  rm = ruby_mod[fqn.rpartition('.').first]
  next unless rm

  by_mod[rm][norm.call(fqn.rpartition('.').last)] = { kind: t['kind'], summary: t.dig('docs', 'summary') }
end

# parent ruby module -> child sub-namespace ruby modules (e.g. AWSCDK::ECR -> [AWSCDK::ECR::Mixins])
ruby_modules = ruby_mod.values.uniq
children = Hash.new { |h, k| h[k] = [] }
ruby_modules.each do |rm|
  parts = rm.split('::')
  children[parts[0..-2].join('::')] << rm if parts.length > 2
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
  .row.ns .n::before{content:"\\2325\\A0";color:var(--muted)}
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
ruby_modules.sort.each do |rm|
  segs = rm.split('::')[1..]                 # ["ECR"] or ["ECR", "Mixins"]
  dir = File.join(awscdk, *segs)
  next unless File.directory?(dir)

  info = by_mod[rm]
  child_leaves = children[rm].map { |c| c.split('::').last }

  types = Dir.glob(File.join(dir, '*.html')).filter_map do |f|
    base = File.basename(f)
    next if base == 'index.html'

    name = File.basename(f, '.html')
    next if child_leaves.include?(name)      # skip child-namespace pages (e.g. Mixins.html)

    meta = info[norm.call(name)] || {}
    { name: name, href: base, kind: meta[:kind], summary: meta[:summary] }
  end
  next if types.empty? && children[rm].empty?

  by_kind = types.group_by { |c| c[:kind] }
  sections = []

  # Namespaces first — they're navigation, above the module's own types.
  unless children[rm].empty?
    ns_rows = children[rm].sort.map do |c|
      leaf = c.split('::').last
      %(<a class="row ns" href="#{leaf}/index.html"><span class="n">#{esc.call(leaf)}</span></a>)
    end.join("\n      ")
    sections << %(<h2 class="sec">Namespaces <span class="ct">#{children[rm].length}</span></h2>\n      #{ns_rows})
  end

  SECTIONS.each do |kind, label|
    items = by_kind[kind]
    next if items.nil? || items.empty?

    sections << %(<h2 class="sec">#{label} <span class="ct">#{items.length}</span></h2>\n      #{render_rows.call(items)})
  end
  other = types.reject { |c| SECTIONS.map(&:first).include?(c[:kind]) }
  sections << %(<h2 class="sec">Other <span class="ct">#{other.length}</span></h2>\n      #{render_rows.call(other)}) if other.any?

  # Breadcrumb: AWSCDK / <seg> / ... / <current>, each linked to its own landing.
  crumb = [%(<a href="#{'../' * segs.length}index.html">AWSCDK</a>)]
  segs.each_with_index do |seg, i|
    crumb << if i == segs.length - 1
               %(<span class="cur">#{esc.call(seg)}</span>)
             else
               %(<a href="#{'../' * (segs.length - 1 - i)}index.html">#{esc.call(seg)}</a>)
             end
  end
  crumb = %(<nav class="cdk-crumb">#{crumb.join('<span class="sep">/</span>')}</nav>)

  File.write(File.join(dir, 'index.html'), <<~HTML)
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{esc.call(rm)} — AWS CDK for Ruby</title>
    <style>#{STYLE}</style></head><body><div class="wrap">
      #{crumb}
      <h1>#{esc.call(rm)}</h1>
      <p class="sub">#{types.length} types</p>
      #{sections.join("\n      ")}
      <footer>Generated on #{Time.now.strftime('%a %b %d %H:%M:%S %Y')}.</footer>
    </div></body></html>
  HTML
  count += 1
end
puts "wrote #{count} namespace landings"
