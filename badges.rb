require "multi_json"
require_relative "badge_methods"

$paths = [
  "windows",
  "linux",
  "macos",
  "solaris",
  "devel",
  "release",
  "r-devel-linux-x86_64-debian-clang",
  "r-devel-linux-x86_64-debian-gcc",
  "r-devel-linux-x86_64-fedora-clang",
  "r-devel-linux-x86_64-fedora-gcc",
  "r-devel-windows-ix86+x86_64",
  "r-oldrel-macos-x86_64",
  "r-oldrel-windows-ix86+x86_64",
  "r-patched-linux-x86_64",
  "r-release-linux-x86_64",
  "r-release-macos-x86_64",
  "r-release-windows-ix86+x86_64"]

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

def mkdir_if(path)
  full_path = "svgs/badges/flavor/" + path
  puts full_path
  Dir.exist?(full_path) ? nil : Dir.mkdir(full_path)
end

def make_svgs
  pkgs = []
  File.open("names.txt", "r") do |f|
    f.each_line do |line|
      pkgs << line.chomp.gsub(/"/, '')
    end
  end
  
  $paths.map { |e| mkdir_if(e) }
  
  pkgs.map { |pkg|
    svg = badge_create_type(pkg, 'summary')
    File.open("svgs/badges/summary/" + pkg + ".svg", 'w') { |f| f.puts svg }
    
    svg = badge_create_type(pkg, 'worst')
    File.open("svgs/badges/worst/" + pkg + ".svg", 'w') { |f| f.puts svg }

    $paths.map { |path| 
      svg = badge_create_flavor(pkg, path)
      File.open("svgs/badges/flavor/%s/" % path + pkg + ".svg", 'w') { |f| f.puts svg }  
    }
  }
end
