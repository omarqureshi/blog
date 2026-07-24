#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the human-facing landing page (index.html) for the gem feed at
# https://rubygems.omarqureshi.net. The feed otherwise answers only the machine
# RubyGems endpoints (/versions, /info/<gem>, /gems/<gem>.gem, specs.4.8.gz);
# this gives a person browsing the host a real page: install snippet, links to
# the docs + RFC, and every published gem with all its versions (newest first).
#
# Data source: the compact-index Marshal files the publish pipeline regenerates
# right before upload — specs.4.8.gz (release-style builds) and
# prerelease_specs.4.8.gz (historical 0.0.0.pre.* builds). Each is an array of
# [name, Gem::Version, platform]. No network, no gem metadata beyond the index.
#
# Usage: ruby gen-feed-index.rb <repo-dir>
#   <repo-dir> holds specs.4.8.gz / prerelease_specs.4.8.gz and gems/; index.html
#   is written into it so the pipeline's `aws s3 sync` uploads it to the root.

require 'zlib'
require 'stringio'
require 'rubygems'
require 'fileutils'

repo_dir = ARGV[0] or abort('usage: gen-feed-index.rb <repo-dir>')
script_dir = __dir__

def load_specs(path)
  return [] unless File.exist?(path)
  Marshal.load(Zlib::GzipReader.new(StringIO.new(File.binread(path))).read)
end

entries = %w[specs.4.8.gz prerelease_specs.4.8.gz]
          .flat_map { |f| load_specs(File.join(repo_dir, f)) }

# name => sorted-desc list of Gem::Version
by_gem = entries.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, ver, _plat), acc|
  acc[name] << ver
end
by_gem.each_value { |vs| vs.replace(vs.uniq.sort.reverse) }

# The build timestamp is embedded in the version: 0.0.0.<YYYYMMDDHHMMSS> (or the
# historical 0.0.0.pre.<ts>). Pull the first 14-digit run and render it as a UTC
# date; versions without one (e.g. a bare 0.0.0) just show no date.
def build_date(version)
  m = version.to_s.match(/(\d{14})/) or return nil
  t = m[1]
  "#{t[0, 4]}-#{t[4, 2]}-#{t[6, 2]} #{t[8, 2]}:#{t[10, 2]}:#{t[12, 2]} UTC"
end

def esc(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
end

# Order the gems so aws-cdk-lib leads, then the rest of the CDK closure, then
# anything else alphabetically.
LEAD = %w[
  aws-cdk-lib constructs jsii-ruby-runtime
  aws-cdk-asset-awscli-v1 aws-cdk-asset-node-proxy-agent-v6 aws-cdk-cloud-assembly-schema
].freeze
ordered = by_gem.keys.sort_by { |n| [LEAD.index(n) || LEAD.size, n] }

total_gems = ordered.size
total_versions = by_gem.values.sum(&:size)

sections = ordered.map do |name|
  versions = by_gem[name]
  latest = versions.first
  latest_date = build_date(latest)
  rows = versions.map do |v|
    d = build_date(v)
    date_cell = d ? %(<span class="d">#{d}</span>) : ''
    %(<li><a href="gems/#{esc(name)}-#{esc(v)}.gem"><code>#{esc(v)}</code></a>#{date_cell}</li>)
  end.join("\n            ")

  <<~SECTION
    <section class="gem" id="#{esc(name)}">
      <h3><code>#{esc(name)}</code><span class="count">#{versions.size} version#{versions.size == 1 ? '' : 's'}</span></h3>
      <p class="latest">latest <a href="gems/#{esc(name)}-#{esc(latest)}.gem"><code>#{esc(latest)}</code></a>#{latest_date ? " <span class=\"d\">#{latest_date}</span>" : ''}</p>
      <details>
        <summary>all versions</summary>
        <ul class="vers">
            #{rows}
        </ul>
      </details>
    </section>
  SECTION
end.join("\n")

install = <<~RUBY.strip
  source "https://rubygems.org"

  # Everything the CDK needs rides in as pinned transitive dependencies.
  gem "aws-cdk-lib", source: "https://rubygems.omarqureshi.net"
RUBY

html = <<~HTML
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AWS CDK for Ruby — Gem Feed</title>
  <link rel="stylesheet" href="/feed-index.css">
  </head><body><div class="wrap">
    <h1>AWS CDK for <span class="r">Ruby</span> — gem feed</h1>
    <p class="sub">A credential-free preview gem feed for the native Ruby bindings of the AWS CDK.</p>
    <nav class="links">
      <a href="/docs/">API documentation ↗</a>
      <a href="https://github.com/aws/aws-cdk-rfcs/pull/939">RFC ↗</a>
      <a href="#gems">Published gems ↓</a>
    </nav>

    <h2 id="install">Getting started</h2>
    <p>Add one line to your <code>Gemfile</code> and run <code>bundle install</code> — the rest of the closure
       (constructs, the asset packages, the jsii runtime) arrives as pinned transitive dependencies:</p>
    <pre class="cb"><code><span class="k">source</span> <span class="s">"https://rubygems.org"</span>

  <span class="c"># Everything the CDK needs rides in as pinned transitive dependencies.</span>
  <span class="k">gem</span> <span class="s">"aws-cdk-lib"</span>, <span class="k">source:</span> <span class="s">"https://rubygems.omarqureshi.net"</span></code></pre>
    <p class="meta">Preview builds carry release-style versions (<code>0.0.0.&lt;timestamp&gt;</code>); a bare requirement
       resolves the newest, and <code>bundle update aws-cdk-lib</code> adopts a later one.</p>

    <h2 id="gems">Published gems</h2>
    <p class="meta">#{total_gems} gems, #{total_versions} versions total.</p>
    #{sections}

    <footer>Regenerated on every publish. Machine endpoints: <code>/versions</code>, <code>/info/&lt;gem&gt;</code>, <code>/specs.4.8.gz</code>.</footer>
  </div></body></html>
HTML

out = File.join(repo_dir, 'index.html')
File.write(out, html)
# Ship the stylesheet next to it so `aws s3 sync` uploads both to the feed root.
FileUtils.cp(File.join(script_dir, 'feed-index.css'), File.join(repo_dir, 'feed-index.css'))
warn "wrote #{out} (+ feed-index.css): #{total_gems} gems, #{total_versions} versions"
