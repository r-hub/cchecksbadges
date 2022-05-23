require_relative 'scrape'
require_relative 'badges'

require 'rake/testtask'

desc "scrape html files"
task :scrape do
  begin
    scrape_all
  rescue Exception => e
    raise e
  end
end


desc "make svgs"
task :makesvgs do
  begin
    make_svgs
  rescue Exception => e
    raise e
  end
end
