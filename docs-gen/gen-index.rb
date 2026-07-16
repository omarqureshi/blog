#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Assembly-driven root index -> <out>/AWSCDK/index.html
# Walks the jsii assembly's submodules for authoritative Ruby module names; links the
# modules whose docs are built under <out>/AWSCDK/<Module>/. Prepends a hand-written
# "Getting started" section (install, a first stack, deploy, naming rules).
#
#   gen-index.rb <assembly.jsii(.gz)> <out-dir>
require 'json'
require 'zlib'
require 'set'

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

code = ->(text) { %(<pre class="cb"><code>#{esc.call(text)}</code></pre>) }

gemfile = <<~RUBY
  source 'https://rubygems.org'

  source 'https://rubygems.omarqureshi.net' do
    gem 'aws-cdk-lib', '>= 0.0.0.pre'
    gem 'constructs', '>= 0.0.0.pre'
    gem 'jsii-ruby-runtime', '>= 0.0.0.pre'

    # aws-cdk-lib requires these asset packages at load time:
    gem 'aws-cdk-asset-awscli-v1', '>= 0.0.0.pre'
    gem 'aws-cdk-asset-node-proxy-agent-v6', '>= 0.0.0.pre'
    gem 'aws-cdk-cloud-assembly-schema', '>= 0.0.0.pre'
  end
RUBY

stack = <<~RUBY
  # stacks/my_stack.rb
  require 'aws-cdk-lib'

  class MyStack < AWSCDK::Stack
    def initialize(scope, id, props = nil)
      super(scope, id, props)

      AWSCDK::S3::Bucket.new(
        self,
        'MyBucket',
        {
          versioned: true,
          removal_policy: AWSCDK::RemovalPolicy::DESTROY,
          auto_delete_objects: true
        }
      )
    end
  end
RUBY

app = <<~RUBY
  # app.rb
  require 'aws-cdk-lib'
  require_relative 'stacks/my_stack'

  app = AWSCDK::App.new

  MyStack.new(app, 'MyStack', {
    env: AWSCDK::Environment.new(
      account: ENV['CDK_DEFAULT_ACCOUNT'],
      region: ENV.fetch('CDK_DEFAULT_REGION', 'us-east-1')
    )
  })

  app.synth
RUBY

deploy = <<~SH
  $ bundle install
  $ npm install -g aws-cdk @jsii/runtime
  $ cdk deploy
SH

getting_started = <<~HTML
  <section class="gs" id="getting-started">
    <h2>Getting started</h2>
    <p>Native Ruby bindings for the AWS CDK — the same construct library every other CDK
    language uses, generated from jsii. You write idiomatic Ruby and <code>cdk deploy</code>
    synthesises and deploys it exactly as it would from TypeScript.</p>

    <h3>Prerequisites</h3>
    <ul>
      <li><strong>Ruby ≥ 3.3</strong> (MRI / CRuby).</li>
      <li><strong>Node.js</strong> — the bindings talk to the jsii kernel (a small Node sidecar). You never write Node, but it must be installed.</li>
      <li><strong>The CDK CLI</strong>: <code>npm install -g aws-cdk</code>.</li>
    </ul>

    <h3>Gemfile</h3>
    <p>The gems are published to <code>https://rubygems.omarqureshi.net</code>. During the
    preview they're pre-release, hence the <code>>= 0.0.0.pre</code> constraint. Then
    <code>bundle install</code>.</p>
    #{code.call(gemfile)}

    <h3>cdk.json</h3>
    <p>Tells the CDK CLI how to run your app:</p>
    #{code.call(%({\n  "app": "bundle exec ruby app.rb"\n}))}

    <h3>A first stack</h3>
    <p>Subclass <code>AWSCDK::Stack</code>, call <code>super</code>, and instantiate
    constructs with <code>(self, 'LogicalId', props)</code> — the same shape as every
    other CDK language.</p>
    #{code.call(stack)}
    #{code.call(app)}

    <h3>Deploy</h3>
    #{code.call(deploy)}

    <h3>Naming rules</h3>
    <p>The conventions you'll rely on reading these docs:</p>
    <ul>
      <li><strong>Modules</strong> are PascalCase under <code>AWSCDK</code>: <code>AWSCDK::S3</code>, <code>AWSCDK::DynamoDB</code>, <code>AWSCDK::APIGatewayv2</code>.</li>
      <li><strong>AWS acronyms are uppercased — in class names too.</strong> <code>RestApi</code> → <code>AWSCDK::APIGateway::RestAPI</code>; <code>FunctionUrl</code> → <code>AWSCDK::Lambda::FunctionURL</code>; <code>…Arn</code> → <code>…ARN</code>.</li>
      <li><strong>Props</strong> are a Ruby <code>Hash</code> with <strong>snake_case</strong> keys — <code>removal_policy:</code>, not <code>removalPolicy:</code>.</li>
      <li><strong>Enums</strong> are constants under <code>::</code>: <code>AWSCDK::RemovalPolicy::DESTROY</code>.</li>
      <li><strong>Static properties</strong> are method calls with a <code>.</code>: <code>AWSCDK::Lambda::Runtime.RUBY_4_0</code>.</li>
    </ul>
  </section>
HTML

Dir.mkdir(awscdk) unless File.directory?(awscdk)
File.write(File.join(awscdk, 'index.html'), <<~HTML)
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AWS CDK for Ruby — API Reference</title>
  <style>
    :root{color-scheme:light dark;--bg:#fbfbfc;--ink:#1a1a1e;--muted:#70707a;--line:#e6e6ea;--accent:#cc342d;--live:#157f3b;--panel:#f4f4f6}
    @media(prefers-color-scheme:dark){:root{--bg:#131317;--ink:#e9e9ee;--muted:#9a9aa6;--line:#2a2a33;--live:#4ec27a;--panel:#1c1c22}}
    body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,sans-serif}
    .wrap{max-width:1120px;margin:0 auto;padding:2.5rem 1.25rem 4rem}
    h1{font-size:1.9rem;margin:0 0 .2rem;letter-spacing:-.02em}h1 .r{color:var(--accent)}
    p.sub{color:var(--muted);margin:.1rem 0 .8rem}
    .links{margin:.2rem 0 .4rem;font-size:.9rem}
    .links a{color:var(--accent);font-weight:600;text-decoration:none;margin-right:1.1rem}
    .links a:hover{text-decoration:underline}
    .gs{border-top:1px solid var(--line);padding-top:.5rem}
    .gs h2{font-size:1.35rem;margin:1.4rem 0 .5rem;letter-spacing:-.01em}
    .gs h3{font-size:.8rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:700;margin:1.6rem 0 .4rem}
    .gs p{margin:.4rem 0;max-width:70ch}
    .gs ul{margin:.4rem 0;padding-left:1.2rem;max-width:80ch}.gs li{margin:.35rem 0}
    .gs code,.m-title code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--panel);padding:.1em .35em;border-radius:4px;font-size:.88em}
    pre.cb{background:var(--panel);padding:.8rem 1rem;border-radius:8px;overflow-x:auto;margin:.5rem 0;font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace}
    pre.cb code{background:none;padding:0;font-size:inherit}
    .m-title{font-size:1.35rem;margin:2rem 0 .3rem;letter-spacing:-.01em;border-top:1px solid var(--line);padding-top:1.5rem}
    .cols{columns:3 300px;column-gap:1.5rem;margin-top:1rem}
    .m{display:block;padding:.35rem .1rem;color:var(--muted);break-inside:avoid;text-decoration:none;font-family:ui-monospace,monospace;font-size:13px}
    a.m.live{color:var(--ink);font-weight:600}a.m.live:hover{color:var(--accent)}
    .cdk-crumb{margin:0 0 1rem;font:600 .85rem system-ui,-apple-system,sans-serif}
    .cdk-crumb .cur{color:var(--muted);font-weight:400;font-family:ui-monospace,monospace}
    footer{margin-top:2rem;color:var(--muted);font-size:.85rem;border-top:1px solid var(--line);padding-top:1rem;text-align:center}
  </style></head><body><div class="wrap">
    <nav class="cdk-crumb"><span class="cur">AWSCDK</span></nav>
    <h1>AWS CDK for <span class="r">Ruby</span></h1>
    <p class="sub">API reference for the native Ruby bindings of the AWS CDK.</p>
    <nav class="links"><a href="#getting-started">Getting started</a><a href="#modules">Browse #{modules.length} modules ↓</a></nav>
    #{getting_started}
    <h2 class="m-title" id="modules">Modules</h2>
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

puts "AWSCDK/index.html: #{modules.length} modules (#{built.size} linked) + getting-started; root -> redirect"
