#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Inject a working breadcrumb into every YARD class page, replacing YARD's broken
# frame nav (which is hidden by the theme). Paths are computed by depth so nested
# pages (e.g. CfnTable/Prop) link correctly too.
#
#   inject-crumb.rb <out-dir>
out_dir = ARGV[0]
awscdk = File.join(out_dir, 'AWSCDK')
esc = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;') }
count = 0

Dir.glob(File.join(awscdk, '**', '*.html')).each do |f|
  next if File.basename(f) == 'index.html'

  rel = f.sub("#{awscdk}/", '')
  comps = rel.split('/')
  next if comps.length < 2

  mod = comps[0]
  cls = File.basename(f, '.html')
  root_link = ('../' * (comps.length - 1)) + 'index.html'     # -> AWSCDK/index.html
  mod_link  = ('../' * (comps.length - 2)) + 'index.html'     # -> AWSCDK/<mod>/index.html

  crumb = %(<nav class="cdk-crumb">) +
          %(<a href="#{root_link}">AWSCDK</a><span class="sep">/</span>) +
          %(<a href="#{mod_link}">#{esc.call(mod)}</a><span class="sep">/</span>) +
          %(<span class="cur">#{esc.call(cls)}</span></nav>)

  html = File.read(f)
  # Remove any prior crumb (may be at the old body-child location) so this is re-runnable.
  html = html.sub(%r{[ \t]*<nav class="cdk-crumb">.*?</nav>\n?}m, '')
  # Inject INSIDE #main (the content column) — not as a child of <body>, which is a
  # flex container (a body-child crumb becomes a flex sibling of #main -> layout gap).
  main_re = /(<[^>]*\bid="main"[^>]*>)/i
  next unless html =~ main_re

  html = html.sub(main_re) { "#{Regexp.last_match(1)}\n#{crumb}" }
  File.write(f, html)
  count += 1
end

puts "injected breadcrumb into #{count} class pages"
