require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

# Hide warnings emitted from third-party gems (e.g. oga); keep our own.
module GemWarningFilter
  GEM_DIRS = (Gem.path + [Gem.default_dir]).map { |dir| File.join(dir, 'gems') }.uniq.freeze

  def warn(message, **kwargs)
    return if GEM_DIRS.any? { |dir| message.start_with?(dir) }

    super
  end
end
Warning.singleton_class.prepend(GemWarningFilter)

require_relative '../scrape'
require_relative '../badges'

class PipelineTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  FIXTURE = File.join(__dir__, 'fixtures/checks.html')

  def setup
    @body = scrape_pkg_body(FIXTURE)
  end

  def assert_badge(svg, message, color)
    document = Oga.parse_xml(svg)
    assert_equal 'svg', document.children.first.name
    assert_equal ['CRAN', 'CRAN', message, message],
                 document.xpath('//text').map { |node| node.text.strip }
    assert_includes document.xpath('//path').map { |node| node.get('fill') }, color
    refute_match(/:(?:text|color|width|textwidth|path_d|message):/, svg)
  end

  def test_scrape_parses_summary_and_all_statuses
    assert_equal 'checks', @body['package']
    assert_equal 'https://cloud.r-project.org/web/checks/check_results_checks.html', @body['url']
    assert_equal(
      { 'any' => true, 'ok' => 1, 'note' => 1, 'warn' => 1, 'error' => 1, 'fail' => 1 },
      @body['summary']
    )
    assert_equal %w[OK NOTE WARN ERROR FAIL], @body['checks'].map { |check| check['status'] }
  end

  def test_scrape_parses_flavors_numbers_and_urls
    assert_equal(
      { 'flavor' => 'r-devel-linux-x86_64-debian-clang', 'version' => '1.0',
        'tinstall' => 1.25, 'tcheck' => 2.5, 'ttotal' => 3.75, 'status' => 'OK',
        'check_url' => 'https://example.org/linux/demo.html' },
      @body['checks'].first
    )
    assert_equal 0.0, @body['checks'].last['tinstall']
    assert_equal 0.0, @body['checks'].last['tcheck']
  end

  def test_scrape_handles_missing_results
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'missing.html')
      File.write(path, '<html><body>No results</body></html>')
      assert_equal({ 'package' => 'missing', 'checks' => nil }, scrape_pkg_body(path))
    end
  end

  def test_summary_badges
    assert_badge do_badge('checks', false, nil, @body), 'Not OK', '#e05d44'
    @body['summary']['any'] = false
    assert_badge do_badge('checks', false, nil, @body), 'OK', '#4c1'
  end

  def test_summary_can_ignore_notes
    @body['summary'].merge!('warn' => 0, 'error' => 0, 'fail' => 0)
    assert_badge do_badge('checks', 'true', nil, @body), 'OK', '#4c1'
    assert_badge do_badge('checks', 'false', nil, @body), 'Not OK', '#e05d44'
  end

  def test_worst_badges_follow_severity
    { 'error' => ['ERROR', '#e05d44'], 'warn' => ['WARN', '#dfb317'],
      'note' => ['NOTE', '#007ec6'] }.each do |status, (message, color)|
      assert_badge do_badge_worst('checks', nil, @body), message, color
      @body['summary'][status] = 0
    end
    assert_badge do_badge_worst('checks', nil, @body), 'OK', '#4c1'
  end

  def test_flavor_badges
    assert_badge do_badge_flavor('checks', 'linux', false, @body), 'Not OK', '#e05d44'
    assert_badge do_badge_flavor('checks', 'debian-clang', false, @body), 'OK', '#4c1'
    assert_badge do_badge_flavor('checks', 'r-release-windows', false, @body), 'Not OK', '#e05d44'
    assert_badge do_badge_flavor('checks', 'r-release-windows', true, @body), 'OK', '#4c1'
    assert_badge do_badge_flavor('checks', 'solaris', false, @body), 'unknown', '#D6D5D6'
  end

  def test_unknown_badges
    [nil, {}, { 'checks' => nil }].each do |body|
      assert_badge do_badge('missing', false, nil, body), 'unknown', '#D6D5D6'
      assert_badge do_badge_worst('missing', nil, body), 'unknown', '#D6D5D6'
      assert_badge do_badge_flavor('missing', 'linux', false, body), 'unknown', '#D6D5D6'
    end
  end

  def test_custom_badge_color
    assert_badge make_badge('CRAN', 'OK', 'orange'), 'OK', '#fe7d37'
    assert_badge make_badge('CRAN', 'OK', '#123abc'), 'OK', '#123abc'
  end

  def test_httpx_conversion_and_badge_generation_end_to_end
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p %w[htmls jsons svgs/badges/summary svgs/badges/worst svgs/badges/flavor]
        url = 'https://cloud.r-project.org/web/checks/check_results_demo.html'
        retry_url = 'https://cloud.r-project.org/web/checks/check_results_retry.html'
        records = [
          { 'input' => url, 'status_code' => 200, 'body' => File.read(FIXTURE) },
          { 'input' => retry_url, 'status_code' => 429 },
          { 'input' => url.sub('demo', 'empty'), 'status_code' => 200, 'body' => '' },
          { 'input' => 'https://example.org/other.html', 'body' => 'ignored' },
          { 'body' => 'missing input' }
        ]
        File.write('responses.jsonl', records.map { |record| MultiJson.dump(record) }.join("\n") +
                                     "\nnot json\n\n")
        stdout, stderr, status = Open3.capture3(
          RbConfig.ruby, File.join(ROOT, 'httpx_to_html.rb'), 'responses.jsonl', 'htmls'
        )
        assert status.success?, stderr
        assert_equal "#{retry_url}\n", stdout
        assert_equal ['htmls/demo.html'], list_htmls('htmls/*.html')
        write_to_disk(scrape_pkg_body('htmls/demo.html'))
        assert_equal @body['summary'], MultiJson.load(File.read('jsons/demo.json'))['summary']
        File.write('names.txt', "\"demo\"\n")
        capture_io { make_svgs }
        assert_equal $paths.length + 2, Dir['svgs/badges/**/*.svg'].length
        assert_badge File.read('svgs/badges/summary/demo.svg'), 'Not OK', '#e05d44'
        assert_badge File.read('svgs/badges/worst/demo.svg'), 'ERROR', '#e05d44'
        assert_badge File.read('svgs/badges/flavor/solaris/demo.svg'), 'unknown', '#D6D5D6'
        assert_badge File.read('svgs/badges/flavor/r-devel-linux-x86_64-debian-clang/demo.svg'), 'OK', '#4c1'
      end
    end
  end

  def test_httpx_converter_requires_arguments
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(ROOT, 'httpx_to_html.rb'))
    refute status.success?
    assert_includes stderr, 'usage: httpx_to_html.rb'
  end
end
