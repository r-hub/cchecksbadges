require "multi_json"
require_relative "badge_methods"

def badge_create_type(package, type)
  d = MultiJson.load(File.read("jsons/%s.json" % package))
  if type == "summary"
    do_badge(package, params, d)
  elsif type == "worst"
    do_badge_worst(package, params, d)
  else
    return nil
  end
end

def badge_create_flavor(package, flavor, ignore)
  d = MultiJson.load(File.read("jsons/%s.json" % package))
  do_badge_flavor(package, flavor, ignore, d)
end

def make_svgs
  puts "not done yet"  
end
