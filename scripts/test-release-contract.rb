#!/usr/bin/env ruby
require "open3"
require "tmpdir"
require "fileutils"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SHA = "a" * 64

def run!(*command, chdir: ROOT)
  output, error, status = Open3.capture3(*command, chdir: chdir)
  raise "#{command.first} failed: #{error}" unless status.success?
  output
end

class CaskContract
  attr_reader :values
  def initialize(source, path)
    @values = {}
    @token = File.basename(path, ".rb")
    instance_eval(source, path)
  end

  def cask(token, &block)
    raise "Cask token does not match filename" unless token == @token
    instance_eval(&block)
  end

  def method_missing(name, *arguments, **keywords)
    return @values[name] if arguments.empty? && keywords.empty?
    @values[name] = keywords.empty? ? arguments.first : keywords
  end
end

source = run!("scripts/render-cask.sh", "1.2.3", SHA, "owner/repo")
cask = CaskContract.new(source, "altty.rb")
raise "Wrong default URL" unless cask.values[:url] == "https://github.com/owner/repo/releases/download/1.2.3/Altty-1.2.3-arm64.zip"
local_url = "http://127.0.0.1:8765/Altty-1.2.3-arm64.zip"
local = CaskContract.new(run!("scripts/render-cask.sh", "1.2.3", SHA, "owner/repo", local_url), "altty.rb")
raise "Override URL changed" unless local.values[:url] == local_url

# Validate the actual destinations used by both workflows, including local/previous Casks.
Dir.glob(File.join(ROOT, ".github/workflows/*.yml")).each do |workflow|
  YAML.load_file(workflow).fetch("jobs").each_value do |job|
    job.fetch("steps").each do |step|
      step.fetch("run", "").scan(/render-cask\.sh[^\n]*> "([^"\n]+\.rb)"/).each do |(path)|
        CaskContract.new(source, path)
      end
    end
  end
end

Dir.mktmpdir("altty-tap-contract-") do |tap|
  run!("git", "init", "-q", chdir: tap)
  File.write(File.join(tap, "README.md"), "Test tap\n")
  run!("git", "add", "README.md", chdir: tap)
  commit = ["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "Fixture"]
  run!(*commit, chdir: tap)
  prepare = ["bash", File.join(ROOT, "scripts/prepare-tap-update.sh")]
  run!(*prepare, "1.2.3", SHA, "owner/repo", tap)
  raise "First Cask not staged" unless run!("git", "diff", "--cached", "--name-only", chdir: tap).strip == "Casks/altty.rb"
  run!(*commit, chdir: tap)
  run!(*prepare, "1.2.4", SHA, "owner/repo", tap)
  raise "Updated version missing" unless File.read(File.join(tap, "Casks/altty.rb")).include?('version "1.2.4"')
  run!(*commit, chdir: tap)
  path = File.join(tap, "Casks/altty.rb")
  File.write(path, File.read(path).sub('name "Altty"', 'name "Unexpected"'))
  run!("git", "add", "Casks/altty.rb", chdir: tap)
  run!(*commit, chdir: tap)
  _, _, status = Open3.capture3(*prepare, "1.2.5", SHA, "owner/repo", tap)
  raise "Non-metadata Cask change was accepted" if status.success?
end
puts "Release contracts passed (URLs, initial tap publication, metadata-only upgrade)."
