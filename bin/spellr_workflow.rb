require 'net/http'
require 'json'
require 'time'
require 'pry'

@GITHUB_SHA = ENV["GITHUB_SHA"]
@GITHUB_EVENT_PATH = ENV["GITHUB_EVENT_PATH"]
@GITHUB_TOKEN = ENV["GITHUB_TOKEN"]
@GITHUB_WORKSPACE = ENV["GITHUB_WORKSPACE"] || `pwd`.chomp

@event = JSON.parse(File.read(ENV["GITHUB_EVENT_PATH"]))
@repository = @event["repository"]
@owner = @repository["owner"]["login"]
@repo = @repository["name"]

@check_name = "spellr"

@headers = {
  "Content-Type": 'application/json',
  "Accept": 'application/vnd.github.antiope-preview+json',
  "Authorization": "Bearer #{@GITHUB_TOKEN}",
  "User-Agent": 'spellr-action'
}

def create_check
  body = {
    "name" => @check_name,
    "head_sha" => @GITHUB_SHA,
    "status" => "in_progress",
    "started_at" => Time.now.iso8601
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs"

  puts path.inspect
  puts body.inspect
  puts @headers.inspect
  resp = http.post(path, body.to_json, @headers)

  if resp.code.to_i >= 300
    raise resp.message
  end

  data = JSON.parse(resp.body)
  return data["id"]
end

def update_check(id, conclusion, output)
  body = {
    "name" => @check_name,
    "head_sha" => @GITHUB_SHA,
    "status" => 'completed',
    "completed_at" => Time.now.iso8601,
    "conclusion" => conclusion,
    "output" => output
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs/#{id}"

  resp = http.patch(path, body.to_json, @headers)

  if resp.code.to_i >= 300
    puts body.to_json
    puts resp.body
    raise resp.message
  end
end

def run_spellr
  annotations = []
  normal_output = nil
  wordlist_output = nil
  Dir.chdir(@GITHUB_WORKSPACE) {
    normal_output = `bundle exec spellr`.split("\n")
    wordlist_output = `bundle exec spellr -w`.split("\n")
  }
  conclusion = "success"
  count = 0

  locations = normal_output.map do |line|
    line.split(' ')[0]&.gsub(/\e\[[0-9]+m/, '')
  end

  words = wordlist_output

  words.zip(locations).each do |word, location|
    path, start_line, end_line = location.split(':')
    annotations.push({
                       "path" => path,
                       "start_line" => start_line.to_i,
                       "end_line" => end_line.to_i,
                       "annotation_level" => 'warning',
                       "message" => "#{word} might be a misspelling?"
                     })
    puts annotations.inspect
  end

  output = {
    "title": @check_name,
    "summary": "#{count} offense(s) found",
    "annotations" => annotations
  }

  return { "output" => output, "conclusion" => conclusion }
end

def run
  id = create_check()
  begin
    results = run_spellr()
    conclusion = results["conclusion"]
    output = results["output"]

    update_check(id, conclusion, output)

    fail if conclusion == "failure"
  rescue
    update_check(id, "failure", nil)
    fail
  end
end

run()

