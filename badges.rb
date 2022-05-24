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

def badge_create_flavor(package, flavor)
  ignore = false
  d = MultiJson.load(File.read("jsons/%s.json" % package))
  do_badge_flavor(package, flavor, ignore, d)
end

def make_svgs
  pkgs = []
  File.open("names.txt", "r") do |f|
    f.each_line do |line|
      pkgs << line.chomp.gsub(/"/, '')
    end
  end
  pkgs.map { |e|
    svg = badge_create_type(e, 'summary')
    File.open("svgs/badges/summary/" + e + ".svg", 'w') { |f| f.puts svg }
    
    svg = badge_create_type(e, 'worst')
    File.open("svgs/badges/worst/" + e + ".svg", 'w') { |f| f.puts svg }

    svg = badge_create_flavor(e, 'release')
    File.open("svgs/badges/flavor/release/" + e + ".svg", 'w') { |f| f.puts svg }
  }
end
