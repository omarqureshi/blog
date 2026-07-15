#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Assembly-driven root index -> <out>/AWSCDK/index.html
# Walks the jsii assembly's submodules for authoritative Ruby module names + README
# summaries; links the modules whose docs are built under <out>/AWSCDK/<Module>/.
#
#   gen-index.rb <assembly.jsii(.gz)> <out-dir>
require 'json'
require 'zlib'

assembly_path, out_dir = ARGV
awscdk = File.join(out_dir, 'AWSCDK')
raw = File.binread(assembly_path)
assembly = JSON.parse(raw[0, 2].bytes == [0x1f, 0x8b] ? Zlib.gunzip(raw) : raw)

modules = assembly.fetch('submodules', {}).values.filter_map do |sub|
  name = sub.dig('targets', 'ruby', 'module')
  next unless name
  # Only top-level modules (AWSCDK::X). Nested sub-namespaces like AWSCDK::ECR::Mixins
  # are listed on their parent module's page, not here.
  next unless name.split('::').length == 2

  { name: name, leaf: name.split('::').last }
end.uniq { |m| m[:name] }.sort_by { |m| m[:name].downcase }

built = File.directory?(awscdk) ? Dir.children(awscdk).select { |d| File.directory?(File.join(awscdk, d)) } : []
built = built.to_set

esc = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
cells = modules.map do |m|
  if built.include?(m[:leaf])
    %(<a class="m live" href="#{m[:leaf]}/index.html">#{esc.call(m[:name])}</a>)
  else
    %(<span class="m">#{esc.call(m[:name])}</span>)
  end
end.join("\n    ")

Dir.mkdir(awscdk) unless File.directory?(awscdk)
File.write(File.join(awscdk, 'index.html'), <<~HTML)
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AWS CDK for Ruby — API Reference</title>
  <style>
    :root{color-scheme:light dark;--bg:#fbfbfc;--ink:#1a1a1e;--muted:#70707a;--line:#e6e6ea;--accent:#cc342d;--live:#157f3b}
    @media(prefers-color-scheme:dark){:root{--bg:#131317;--ink:#e9e9ee;--muted:#9a9aa6;--line:#2a2a33;--live:#4ec27a}}
    body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,sans-serif}
    .wrap{max-width:1120px;margin:0 auto;padding:2.5rem 1.25rem 4rem}
    h1{font-size:1.9rem;margin:0 0 .2rem;letter-spacing:-.02em}h1 .r{color:var(--accent)}
    p.sub{color:var(--muted);margin:.1rem 0 1rem}
    .links a{color:var(--accent);font-weight:600;text-decoration:none;margin-right:1.1rem}
    .cols{columns:3 300px;column-gap:1.5rem;margin-top:1.5rem;border-top:1px solid var(--line);padding-top:1.25rem}
    .m{display:block;padding:.35rem .1rem;color:var(--muted);break-inside:avoid;text-decoration:none;font-family:ui-monospace,monospace;font-size:13px}
    a.m.live{color:var(--ink);font-weight:600}a.m.live:hover{color:var(--accent)}
    .cdk-crumb{margin:0 0 1rem;font:600 .85rem system-ui,-apple-system,sans-serif}
    .cdk-crumb a{color:var(--accent);text-decoration:none}
    .cdk-crumb a:hover{text-decoration:underline}
    .cdk-crumb .sep{color:var(--muted);margin:0 .45rem;font-weight:400}
    .cdk-crumb .cur{color:var(--muted);font-weight:400;font-family:ui-monospace,monospace}
    footer{margin-top:2rem;color:var(--muted);font-size:.85rem;border-top:1px solid var(--line);padding-top:1rem;text-align:center}
  </style></head><body><div class="wrap">
    <nav class="cdk-crumb"><span class="cur">AWSCDK</span></nav>
    <h1>AWS CDK for <span class="r">Ruby</span></h1>
    <div class="cols">
    #{cells}
    </div>
    <footer>Generated on #{Time.now.strftime('%a %b %d %H:%M:%S %Y')}.</footer>
  </div></body></html>
HTML
# Redirect the site root to the API index (overwrites YARD's leftover root index.html).
File.write(File.join(out_dir, 'index.html'), <<~HTML)
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=AWSCDK/index.html">
  <link rel="canonical" href="AWSCDK/index.html">
  <title>AWS CDK for Ruby — API Reference</title></head>
  <body><a href="AWSCDK/index.html">AWS CDK for Ruby — API Reference</a></body></html>
HTML

puts "AWSCDK/index.html: #{modules.length} modules (#{built.size} linked); root -> redirect"

