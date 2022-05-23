require "multi_json"
require_relative "badge_methods"

def badge_create_type(package, type)
  ignore = false
  color = nil
  d = MultiJson.load(File.read("jsons/%s.json" % package))
  if type == "summary"
    do_badge(package, ignore, color, d)
  elsif type == "worst"
    do_badge_worst(package, color, d)
  else
    return nil
  end
end

def badge_create_flavor(package, flavor, ignore)
  d = MultiJson.load(File.read("jsons/%s.json" % package))
  do_badge_flavor(package, flavor, ignore, d)
end

def make_svgs
  # puts "not done yet"
  # jsons = Dir["jsons/*.json"]
  # pkgs = jsons.map { |e| e.gsub(/jsons\/|.json/, '') }
  pkgs = []
  File.open("names.txt", "r") do |f|
    f.each_line do |line|
      pkgs << line.chomp.gsub(/"/, '')
    end
  end
  pkgs.map { |e|
    svg = badge_create_type(e, 'summary')
    File.open("svgs/" + e + ".svg", 'w') { |f| f.puts svg }
    # badge_create_type(pkgs.first, 'worst')
  }
end
