require 'net/http'
require 'json'
require 'openssl'
require 'base64'
require 'tmpdir'

ADMIN_LAYOUT = 'src/_layouts/admin.erb'
NPM_REGISTRY = 'https://registry.npmjs.org/decap-cms/latest'
UNPKG_BASE   = 'https://unpkg.com/decap-cms'

desc 'Run feature smoke tests against a built site (defaults to output)'
task :smoke_test, [:build_dir] do |_, args|
  ruby "scripts/smoke_test.rb #{args[:build_dir]}".strip
end

desc 'Check that generated redirects resolve correctly (defaults to localhost:4000)'
task :check_redirects, [:base_url] do |_, args|
  ruby "scripts/check_redirects.rb #{args[:base_url]}".strip
end

desc 'Run smoke tests and redirect checks together'
task verify: [:smoke_test, :check_redirects]

namespace :bridgetown do
  desc 'Build the Bridgetown site into output/'
  task :build do
    sh 'bundle exec bin/bridgetown build'
  end

  desc 'Build frontend assets (esbuild/postcss) for the Bridgetown site'
  task :frontend do
    sh 'npm run esbuild'
  end
end

# `bin/bridgetown dev`/`start` looks for a Rake task named exactly
# "frontend:watcher" to auto-start the esbuild watcher - normally
# provided by bridgetown-core's own bridgetown_tasks.rake via
# `Bridgetown.load_tasks`, which this Rakefile doesn't call (it predates
# the Jekyll removal and there's no reason to add an in-process
# `require "bridgetown"` dependency to a Rakefile that also needs to run
# standalone rake tasks quickly). Silently does nothing without a
# matching task - no error, just a dev server serving
# MISSING_ESBUILD_ASSET forever.
namespace :frontend do
  task :watcher, [:sidecar] do |_, args|
    if args[:sidecar] == true
      Process.detach(Process.spawn('npm run esbuild-dev'))
      sleep 3
    else
      sh 'npm run esbuild-dev'
    end
  end
end

desc 'Upgrade Decap CMS: fetches latest from npm, cross-verifies against unpkg, updates SRI hash'
task :upgrade_decap do
  # Fetch latest version metadata from npm registry (canonical source)
  puts "Fetching latest version from npm registry..."
  meta    = JSON.parse(http_get(NPM_REGISTRY))
  version = meta['version']
  tarball = meta['dist']['tarball']
  puts "Latest: #{version}"

  npm_hash = Dir.mktmpdir do |dir|
    tarball_path = File.join(dir, 'decap.tgz')
    File.write(tarball_path, http_get(tarball), mode: 'wb')
    system('tar', '-xzf', tarball_path, '-C', dir, 'package/dist/decap-cms.js', exception: true)
    digest(File.read(File.join(dir, 'package/dist/decap-cms.js'), mode: 'rb'))
  end
  puts "Hash from npm tarball : sha384-#{npm_hash}"

  # Cross-verify: same bytes must be served by the CDN we reference in the HTML
  puts "Cross-verifying against unpkg..."
  unpkg_hash = digest(http_get("#{UNPKG_BASE}@#{version}/dist/decap-cms.js"))
  puts "Hash from unpkg       : sha384-#{unpkg_hash}"

  abort "\nMISMATCH — npm and unpkg hashes differ, not updating." if npm_hash != unpkg_hash
  puts "Hashes match — safe to update.\n\n"

  integrity = "sha384-#{npm_hash}"
  layout    = File.read(ADMIN_LAYOUT)
  updated   = layout
    .gsub(%r{decap-cms@[\d.]+/dist/decap-cms\.js}, "decap-cms@#{version}/dist/decap-cms.js")
    .gsub(/integrity="sha384-[^"]*"/, %(integrity="#{integrity}"))

  if layout == updated
    puts "Already on #{version}, nothing to do."
  else
    File.write(ADMIN_LAYOUT, updated)
    puts "Updated #{ADMIN_LAYOUT} to #{version} with SRI hash."
    puts "Next: review the diff, commit, and open a PR."
  end
end

def http_get(url, limit = 10)
  raise 'Too many redirects' if limit.zero?

  uri      = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |h| h.get(uri.request_uri) }

  case response
  when Net::HTTPSuccess     then response.body
  when Net::HTTPRedirection then http_get(response['location'], limit - 1)
  else response.error!
  end
end

def digest(content)
  Base64.strict_encode64(OpenSSL::Digest::SHA384.digest(content))
end
