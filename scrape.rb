require "parallel"
require "multi_json"
require "oga"

require_relative 'utils'

class Array
  def count_em(x)
    return self.find_all { |z| z == x }.count
  end
end

def fetch_urls(foo)
  tmp = foo.map { |e| 
    e.xpath('./td//a[contains(., "OK") or contains(., "ERROR") or contains(., "NOTE") or contains(., "WARN") or contains(., "FAIL")]') 
  }
  tmp = tmp.keep_if { |e| e.length > 0 }
  xx = tmp.map { |e| e.attribute('href')[0].text }
  return xx
end

def scrape_pkg_body(z)
  base_url = 'https://cloud.r-project.org/web/checks/check_results_%s.html'
  
  sub_str = "https-cloud-r-project-org-web-checks-check-results-"
  pkg = z.split('/').last.sub(/-html$/, "").sub(sub_str, "").gsub("-", ".")

  html = Oga.parse_html(File.read(z).force_encoding 'UTF-8');
  tr = html.xpath('//table//tr');
  if tr.length == 0
    return {"package" => pkg, "checks" => nil}
  end
  rws = tr.map { |e| e.xpath('./td//text()').map { |w| w.text }  }.keep_if { |a| a.length > 0 }
  rws = rws.map { |e| e.map { |f| f.lstrip } }
  rws = rws.map { |e| [e[2], e[3], e[4], e[5], e[6], e[9]] }
  nms = tr[0].text.split(' ')
  nms.pop
  res = rws.map { |e| Hash[nms.zip(e)] }

  # get urls and join to dataset
  hrefs = fetch_urls(tr)
  hrefs.each_with_index do |val, i|
    res[i].merge!({"check_url" => hrefs[i]})
  end

  # lowercase all keys
  res.map { |a| a.keys.map { |k| a[k.downcase] = a.delete k } };
  # strip all whitespace
  res.map { |a| a.map { |k, v| a[k] = v.strip } };
  # numbers are numbers
  res.map { |a| a.map { |k, v| a[k] = v.to_f if k.match(/tinstall|tcheck|ttotal/) } };

  # make summary
  stats = res.map { |a| a['status'] }.map(&:downcase)
  summary = {
    "any" => stats.count_em("ok") != stats.length,
    "ok" => stats.count_em("ok"),
    "note" => stats.count_em("note"), 
    "warn" => stats.count_em("warn"), 
    "error"=> stats.count_em("error"),
    "fail"=> stats.count_em("fail")
  }

  return {"package" => pkg, "url" => base_url % pkg, "summary" => summary, "checks" => res}
end

def write_to_disk(x)
  File.open("jsons/%s.json" % x['package'], "w") do |f|
    f.write(MultiJson.dump(x))
  end
end

def scrape_all
  htmls = list_htmls("/tmp/htmls/*");
  pat = "/tmp/htmls/https-cloud-r-project-org-web-checks-check-results-html"
  htmls.reject! { |z| z.match(/results-html$/) }; nil
  out = Parallel.map(htmls, in_processes: 2) { |e| scrape_pkg_body(e) }; nil
  # pkg_names = out.map { |e| e['package'] }
  # File.open("package_names.txt", 'w') { |file| file.write(pkg_names) }
  out.map { |e| write_to_disk(e) }
end
