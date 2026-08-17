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
end

puts "\n#{redirects.size - failures}/#{redirects.size} redirects passed against #{base_url}"
exit(failures.zero? ? 0 : 1)
