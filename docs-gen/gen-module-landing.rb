#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Per-namespace landing pages, driven by the YARD output tree (so it also covers
# namespaces the assembly doesn't tag with a Ruby module — e.g. the ~280 per-service
# sub-namespaces under `interfaces`). Walks AWSCDK/**: a subdir is a namespace unless
# its sibling <X>.html is a "Class:" page (that's a class's nested-types dir, e.g.
# CfnTable). Each landing lists child namespaces + classes/interfaces/enums. Kind and
# summary come from the assembly where available, else the YARD page type.
#
#   gen-module-landing.rb <assembly.jsii(.gz)> <out-dir>
require 'json'
require 'zlib'
require 'set'

assembly_path, out_dir = ARGV
awscdk = File.join(out_dir, 'AWSCDK')
raw = File.binread(assembly_path)
assembly = JSON.parse(raw[0, 2].bytes == [0x1f, 0x8b] ? Zlib.gunzip(raw) : raw)

norm = ->(s) { s.downcase.gsub(/[^a-z0-9]/, '') }
ruby_mod = {}
assembly.fetch('submodules', {}).each { |fqn, s| (rm = s.dig('targets', 'ruby', 'module')) && (ruby_mod[fqn] = rm) }

by_mod = Hash.new { |h, k| h[k] = {} }
assembly.fetch('types', {}).each do |fqn, t|
  rm = ruby_mod[fqn.rpartition('.').first]
  next unless rm

  by_mod[rm][norm.call(fqn.rpartition('.').last)] = { kind: t['kind'], summary: t.dig('docs', 'summary') }
end

esc = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
SECTIONS = [['class', 'Classes'], ['interface', 'Interfaces'], ['enum', 'Enums']].freeze

STYLE = <<~CSS
  :root{color-scheme:light dark;--bg:#fbfbfc;--ink:#1a1a1e;--muted:#70707a;--line:#e6e6ea;--accent:#cc342d;--panel:#f4f4f6;--tok-const:#6f42c1;--tok-str:#0a7d33;--tok-sym:#b5690a;--tok-num:#0a5fb4}
  @media(prefers-color-scheme:dark){:root{--bg:#131317;--ink:#e9e9ee;--muted:#9a9aa6;--line:#2a2a33;--panel:#1c1c22;--tok-const:#b392f0;--tok-str:#7ec97e;--tok-sym:#e0a458;--tok-num:#79b8ff}}
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
  .readme{margin:.5rem 0 1rem;line-height:1.6;overflow-wrap:break-word}
  .readme h1{font-size:1.35rem;font-family:inherit;margin:1.4rem 0 .5rem}
  .readme h2{font-size:1.12rem;font-weight:700;color:var(--ink);text-transform:none;letter-spacing:0;margin:1.3rem 0 .4rem}
  .readme h3{font-size:1rem;font-weight:700;margin:1.1rem 0 .35rem}
  .readme p,.readme li{color:var(--ink)}
  .readme a{color:var(--accent);text-decoration:none} .readme a:hover{text-decoration:underline}
  .readme table{border-collapse:collapse;display:block;overflow-x:auto} .readme th,.readme td{border:1px solid var(--line);padding:.35rem .6rem}
  .readme blockquote{border-left:3px solid var(--line);margin:.6rem 0;padding:.1rem 0 .1rem 1rem;color:var(--muted)}
  .readme pre.code,.readme pre{background:var(--panel);padding:.75rem 1rem;border-radius:6px;overflow-x:auto;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
  .readme :not(pre)>code{background:var(--panel);padding:.12em .35em;border-radius:4px;font:0.9em ui-monospace,SFMono-Regular,Menlo,monospace}
  .readme pre code{background:none;padding:0}
  pre.code .kw{color:var(--accent)} pre.code .const{color:var(--tok-const)}
  pre.code .tstring,pre.code .tstring_content,pre.code .tstring_beg,pre.code .tstring_end,pre.code .regexp{color:var(--tok-str)}
  pre.code .symbol,pre.code .ivar{color:var(--tok-sym)} pre.code .int,pre.code .float{color:var(--tok-num)}
  pre.code .comment,pre.code .info{color:var(--muted);font-style:italic} pre.code .label{color:var(--tok-sym)}
  pre.code .op,pre.code .period,pre.code .comma,pre.code .lparen,pre.code .rparen,pre.code .lbrace,pre.code .rbrace,pre.code .lbracket,pre.code .rbracket{color:var(--muted)}
  pre.code .id{color:var(--ink)} pre.code .object_link a{color:var(--tok-const)}
CSS

# YARD page kind from its <h1>: Class -> class; Module -> (jsii) interface; else nil.
page_kind = lambda do |html_path|
  return nil unless File.exist?(html_path)

  head = File.read(html_path, 8192)   # <h1> sits after YARD's head; read enough to reach it
  if head =~ /<h1>\s*Class:/ then 'class'
  elsif head =~ /<h1>\s*Module:/ then 'interface'
  end
end
class_page = ->(p) { page_kind.call(p) == 'class' }

render_rows = lambda do |items|
  items.sort_by { |c| c[:name].downcase }.map do |c|
    summary = c[:summary] ? %(<span class="s">#{esc.call(c[:summary][0, 90])}</span>) : ''
    %(<a class="row" href="#{c[:href]}"><span class="n">#{esc.call(c[:name])}</span>#{summary}</a>)
  end.join("\n      ")
end

count = 0
process = lambda do |dir|
  segs = dir.sub(%r{\A#{Regexp.escape(awscdk)}/?}, '').split('/').reject(&:empty?)
  rm = (['AWSCDK'] + segs).join('::')
  info = by_mod[rm]

  # A subdir is a namespace unless it's a type's nested-types dir: excluded if the
  # assembly knows a type by that name here (e.g. CfnTable), or its sibling <X>.html
  # is a "Class:" page. Interface sub-namespaces (no assembly ruby.module) fall through.
  child_ns = Dir.children(dir).select do |e|
    File.directory?(File.join(dir, e)) &&
      !info.key?(norm.call(e)) &&
      !class_page.call(File.join(dir, "#{e}.html"))
  end.sort
  ns_set = child_ns.to_set

  types = Dir.glob(File.join(dir, '*.html')).filter_map do |f|
    base = File.basename(f)
    next if base == 'index.html'

    name = File.basename(f, '.html')
    next if ns_set.include?(name)   # namespace page, listed under Namespaces instead

    meta = info[norm.call(name)] || {}
    { name: name, href: base, kind: meta[:kind] || page_kind.call(f), summary: meta[:summary] }
  end
  return if types.empty? && child_ns.empty?

  sections = []
  unless child_ns.empty?
    ns_rows = child_ns.map { |n| %(<a class="row ns" href="#{n}/index.html"><span class="n">#{esc.call(n)}</span></a>) }.join("\n      ")
    sections << %(<h2 class="sec">Namespaces <span class="ct">#{child_ns.length}</span></h2>\n      #{ns_rows})
  end
  by_kind = types.group_by { |c| c[:kind] }
  SECTIONS.each do |kind, label|
    items = by_kind[kind]
    next if items.nil? || items.empty?

    sections << %(<h2 class="sec">#{label} <span class="ct">#{items.length}</span></h2>\n      #{render_rows.call(items)})
  end
  other = types.reject { |c| SECTIONS.map(&:first).include?(c[:kind]) }
  sections << %(<h2 class="sec">Other <span class="ct">#{other.length}</span></h2>\n      #{render_rows.call(other)}) if other.any?

  crumb = [%(<a href="#{'../' * segs.length}index.html">AWSCDK</a>)]
  segs.each_with_index do |seg, i|
    crumb << (i == segs.length - 1 ? %(<span class="cur">#{esc.call(seg)}</span>) : %(<a href="#{'../' * (segs.length - 1 - i)}index.html">#{esc.call(seg)}</a>))
  end
  crumb = %(<nav class="cdk-crumb">#{crumb.join('<span class="sep">/</span>')}</nav>)

  sub = [(child_ns.any? ? "#{child_ns.length} namespaces" : nil), "#{types.length} types"].compact.join(' · ')

  # A module README (if pacmak emitted one) lands on YARD's module page —
  # "<dir>.html", the sibling of this landing. Lift its rendered discussion
  # block onto the landing and drop the now-orphan page. Its links are relative
  # to the module page, which sits one level above the landing, so bump each
  # relative href/src by one `../`.
  readme = ''
  module_page = "#{dir}.html"
  if File.exist?(module_page)
    html = File.read(module_page)
    if (m = html.match(%r{<div class="discussion">(.*?)</div>\s*</div>}m)) && !m[1].strip.empty?
      inner = m[1].strip.gsub(/\b(href|src)="(?!https?:|mailto:|#|\/)/, '\1="../')
      readme = %(<section class="readme">\n      #{inner}\n      </section>\n      )
    end
    File.delete(module_page)
  end

  File.write(File.join(dir, 'index.html'), <<~HTML)
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{esc.call(rm)} — AWS CDK for Ruby</title>
    <style>#{STYLE}</style></head><body><div class="wrap">
      #{crumb}
      <h1>#{esc.call(rm)}</h1>
      <p class="sub">#{sub}</p>
      #{readme}#{sections.join("\n      ")}
      <footer>Generated on #{Time.now.strftime('%a %b %d %H:%M:%S %Y')}.</footer>
    </div></body></html>
  HTML
  count += 1

  child_ns.each { |n| process.call(File.join(dir, n)) }
end

Dir.children(awscdk)
   .select { |d| File.directory?(File.join(awscdk, d)) && !class_page.call(File.join(awscdk, "#{d}.html")) }
   .sort.each { |m| process.call(File.join(awscdk, m)) }

puts "wrote #{count} namespace landings"
