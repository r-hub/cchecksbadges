#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns a JSONL file produced by httpx (https://github.com/projectdiscovery/httpx),
# run with `-json -irr`, into one .html file per package (matching the naming
# scrape.rb expects), and prints any URL that came back with a 429 status to
# stdout so the caller (scrape_pkgs.sh) can retry it.
#
# Usage: ruby httpx_to_html.rb <jsonl_file> <output_dir>

require "json"

jsonl_file, output_dir = ARGV
abort "usage: httpx_to_html.rb <jsonl_file> <output_dir>" unless jsonl_file && output_dir

# pulls the package name back out of a check_results URL, e.g.
# https://cloud.r-project.org/web/checks/check_results_zoo.html -> zoo
def pkg_from_url(url)
  match = url.match(/check_results_(.+)\.html\z/)
  match && match[1]
end

File.foreach(jsonl_file) do |line|
  line.strip!
  next if line.empty?

  record = begin
    JSON.parse(line)
  rescue JSON::ParserError
    next
  end

  url = record["input"]
  next unless url

  if record["status_code"] == 429
    puts url
    next
  end

  body = record["body"]
  next if body.nil? || body.empty?

  pkg = pkg_from_url(url)
  next unless pkg

  File.write(File.join(output_dir, "#{pkg}.html"), body)
end
