#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the placeholder gems that reserve the AWS CDK Ruby bindings names
# on RubyGems.org (see aws/aws-cdk-rfcs#939, "Gem name governance").
#
# Design constraints, all deliberate:
#   * Prerelease version — Bundler and `gem install` never select prereleases
#     by default, so the placeholders cannot pollute anyone's installs.
#   * Authored by Omar, not AWS — claiming a *name* with a documented transfer
#     offer is defensible; publishing anything that presents as AWS is not.
#   * Honest, useful content — each gem's README and require-stub point at the
#     RFC and (where one exists) the working preview channel, so this is a
#     signpost to a real project, not name parking.
#
# Usage: ruby generate.rb    # writes build/<name>/ and pkg/<name>-<v>.gem

require "fileutils"

VERSION = "0.0.0.pre.reserved.1"
RFC_URL = "https://github.com/aws/aws-cdk-rfcs/pull/939"
FEED_URL = "https://rubygems.omarqureshi.net"
AUTHOR = "Omar Qureshi"
EMAIL = "omar@omarqureshi.net"

# on_feed: a working preview of the real gem is installable today.
GEMS = {
  "aws-cdk-lib" => { on_feed: true },
  "constructs" => { on_feed: true },
  "jsii-ruby-runtime" => { on_feed: true },
  "aws-cdk-asset-awscli-v1" => { on_feed: true },
  "aws-cdk-asset-node-proxy-agent-v6" => { on_feed: true },
  "aws-cdk-cloud-assembly-schema" => { on_feed: true },
  "jsii" => { on_feed: false },
  "aws-cdk" => { on_feed: false },
}.freeze

root = __dir__
build_root = File.join(root, "build")
pkg_root = File.join(root, "pkg")
FileUtils.rm_rf([build_root, pkg_root])
FileUtils.mkdir_p(pkg_root)

def preview_snippet(name)
  <<~SNIPPET
    A working preview of the real gem is installable today from the
    credential-free preview channel:

        source "#{FEED_URL}" do
          gem "#{name}", ">= 0.0.0.pre"
        end
  SNIPPET
end

GEMS.each do |name, opts|
  dir = File.join(build_root, name)
  FileUtils.mkdir_p(File.join(dir, "lib"))

  tail = opts[:on_feed] ? preview_snippet(name) : "The RFC above tracks when this name gains a real release.\n"

  description =
    "Name reservation for the AWS CDK Ruby language bindings project while the RFC (#{RFC_URL}) " \
    "is under review; ownership is intended to transfer to AWS. " +
    (opts[:on_feed] ? "A working preview of the real gem is installable today from #{FEED_URL} — see the RFC." : "See the RFC for project status.")

  File.write(File.join(dir, "README.md"), <<~MD)
    # #{name} (reserved)

    This is a **placeholder release** reserving the `#{name}` gem name for the
    AWS CDK Ruby language bindings project, currently under review as
    [aws/aws-cdk-rfcs#939](#{RFC_URL}).

    It contains no functional code, is prerelease-versioned so dependency
    resolution never selects it by default, and carries a standing commitment
    to transfer ownership to AWS (`gem owner --add`) on request.

    #{tail}
  MD

  File.write(File.join(dir, "lib", "#{name}.rb"), <<~RB)
    # frozen_string_literal: true

    # This gem is a name reservation for the AWS CDK Ruby language bindings
    # (#{RFC_URL}). It contains no code.
    raise LoadError, <<~MSG
      '#{name}' #{VERSION} is a placeholder reserving this name for the
      AWS CDK Ruby language bindings (#{RFC_URL}).

      #{tail.strip}
    MSG
  RB

  File.write(File.join(dir, "#{name}.gemspec"), <<~SPEC)
    # frozen_string_literal: true

    Gem::Specification.new do |s|
      s.name        = #{name.inspect}
      s.version     = #{VERSION.inspect}
      s.summary     = "Reserved for the AWS CDK Ruby language bindings (aws/aws-cdk-rfcs#939)"
      s.description = #{description.inspect}
      s.authors     = [#{AUTHOR.inspect}]
      s.email       = [#{EMAIL.inspect}]
      s.homepage    = #{RFC_URL.inspect}
      s.license     = "Apache-2.0"
      s.files       = ["lib/#{name}.rb", "README.md"]
      s.metadata    = {
        "rubygems_mfa_required" => "true",
        "homepage_uri" => #{RFC_URL.inspect},
        "bug_tracker_uri" => "https://github.com/aws/aws-cdk-rfcs/pull/939",
        "documentation_uri" => "#{FEED_URL}/docs",
      }
    end
  SPEC

  ok = system("gem", "build", "#{name}.gemspec", "--output", File.join(pkg_root, "#{name}-#{VERSION}.gem"), chdir: dir, out: File::NULL)
  abort("gem build failed for #{name}") unless ok
  puts "built pkg/#{name}-#{VERSION}.gem"
end

puts "\n#{GEMS.size} placeholder gems built into #{pkg_root}"
puts "Next: see README.md (account setup), then push.sh"
