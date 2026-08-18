require 'net/http'
require 'uri'

REDIRECTS_FILE = File.exist?('src/_redirects') ? 'src/_redirects' : '_redirects'
base_url = ARGV[0] || 'http://localhost:4000'

def parse_redirects(path)
  File.readlines(path).filter_map do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    source, destination, code = line.split(/\s+/)
    { source: source, destination: destination, code: code }
  end
end

def check(base_url, redirect)
  uri = URI.join(base_url, redirect[:source])
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.get(uri.request_uri)
  end

  actual_code = response.code
  actual_location = response['location']
  expected_location = URI.join(base_url, redirect[:destination]).path

  ok = actual_code == redirect[:code] &&
       !actual_location.nil? &&
       URI.join(base_url, actual_location).path == expected_location

  [ok, actual_code, actual_location]
rescue StandardError => e
  [false, "ERROR", e.message]
end

# A redirect can correctly point wherever _redirects says it does and still
# send visitors to a 404 - the destination itself has to actually resolve.
# This is exactly the gap that let 3 of 5 redirects in this file quietly
# point at a page that had since moved to a different date-based permalink
# (see generate_redirects.rb) without either this check or a human noticing.
def check_destination(base_url, redirect)
  uri = URI.join(base_url, redirect[:destination])
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.get(uri.request_uri)
  end

  [response.code == '200', response.code]
rescue StandardError => e
  [false, "ERROR: #{e.message}"]
end

redirects = parse_redirects(REDIRECTS_FILE)
failures = 0

redirects.each do |redirect|
  ok, actual_code, actual_location = check(base_url, redirect)

  if ok
    puts "PASS  #{redirect[:source]} -> #{redirect[:destination]} (#{actual_code})"
  else
    failures += 1
    puts "FAIL  #{redirect[:source]} -> expected #{redirect[:destination]} (#{redirect[:code]}), " \
         "got #{actual_location.inspect} (#{actual_code})"
  end

  dest_ok, dest_code = check_destination(base_url, redirect)
  if dest_ok
    puts "PASS  #{redirect[:destination]} resolves (#{dest_code})"
  else
    failures += 1
    puts "FAIL  #{redirect[:destination]} does not resolve - got #{dest_code}"
  end
end

total = redirects.size * 2
puts "\n#{total - failures}/#{total} checks passed against #{base_url}"
exit(failures.zero? ? 0 : 1)
