#!/usr/bin/env bash
set -euo pipefail

echo "scraping cran pkg check pages"

url='https://crandb.r-pkg.org/-/pkgnames'
url_pat='https://cloud.r-project.org/web/checks/check_results_%s.html\n'
output_dir='/tmp/htmls'
log_dir='/tmp/httpx_logs'

# Root cause of the 429s (see git history for the ganda-based version of this
# script): CloudFront's WAF in front of cloud.r-project.org throttles requests
# that carry the default Go http.Client User-Agent ("Go-http-client/2.0"),
# returning a 429 with "x-ratelimit-limit: 100" and "retry-after: 300". A
# normal browser-ish UA was not throttled at all, even at high concurrency. So
# we always send a real, descriptive UA, and disable httpx's random
# User-Agent feature so it can't reintroduce a UA CloudFront doesn't like.
user_agent='cchecksbadges-scraper/1.0 (+https://github.com/sckott/cchecksbadges)'

# httpx (https://github.com/projectdiscovery/httpx) is built on top of
# projectdiscovery/retryablehttp-go, whose default retry policy only retries
# on connection errors and 5XX responses/timeouts - not 429 (Too Many
# Requests). So, same as with ganda before it, we still need to handle 429
# ourselves. With the UA fix above we shouldn't see 429s anymore, but we keep
# a throttle and a retry loop as a safety net. If we ever do get 429'd again,
# CloudFront told us it wants a 300s (5 minute) cooldown, so the retry loop
# backs off starting from that value rather than guessing.
threads=15
rate_limit=10
retries=2
timeout_secs=15
max_retries=3
base_delay_secs=300

# optional: set LIMIT=2000 (or any number) in the environment to only scrape
# the first N package names, useful for testing before a full run
limit="${LIMIT:-0}"

# ProjectDiscovery's httpx (what we actually want) shares its name with an
# unrelated Python httpx CLI (installed e.g. via `brew install httpx` or
# `pipx install httpx`), and that Python CLI is commonly found earlier on
# $PATH than the Go binary from `go install .../httpx@latest` (which lives in
# `$(go env GOPATH)/bin`, often not on $PATH at all). Just calling `httpx`
# can silently run the wrong tool and fail with something like
# "Error: No such option: -l", so we explicitly resolve and verify the right
# binary here instead. Set HTTPX_BIN to override this detection.
resolve_httpx() {
  local candidates=()
  [ -n "${HTTPX_BIN:-}" ] && candidates+=("$HTTPX_BIN")
  command -v go >/dev/null 2>&1 && candidates+=("$(go env GOPATH 2>/dev/null)/bin/httpx")
  candidates+=("/usr/local/bin/httpx" "$HOME/go/bin/httpx")
  command -v httpx >/dev/null 2>&1 && candidates+=("$(command -v httpx)")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ] && "$candidate" -version 2>&1 | grep -qi projectdiscovery; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

httpx_bin="$(resolve_httpx)" || {
  echo "error: could not find ProjectDiscovery's httpx binary (the CLI on" >&2
  echo "your \$PATH named 'httpx' looks like a different tool)." >&2
  echo "Install it with: go install github.com/projectdiscovery/httpx/cmd/httpx@latest" >&2
  echo "and either add \$(go env GOPATH)/bin to \$PATH, or set HTTPX_BIN to its full path." >&2
  exit 1
}
echo "using httpx binary: $httpx_bin"

rm -rf "$output_dir" "$log_dir"
mkdir -p "$output_dir" "$log_dir"

curl "$url" > names.json
jq -r '. | keys[]' names.json > names.txt

if [ "$limit" -gt 0 ]; then
  echo "LIMIT set, only scraping first $limit package names"
  head -n "$limit" names.txt > names_subset.txt
  mv names_subset.txt names.txt
fi

xargs printf "$url_pat" < names.txt > urls.txt

# runs httpx against $1 (a file of urls), writing JSONL results to $2.
# `-irr` makes httpx include the decoded response body directly in the JSON
# output (as a "body" field), so we don't need a separate store-response
# step or have to strip HTTP headers back out of a raw response dump.
run_httpx() {
  local input_file="$1"
  local json_out="$2"
  local t="$3"
  local rl="$4"

  "$httpx_bin" \
    -list "$input_file" \
    -header "User-Agent: $user_agent" \
    -random-agent=false \
    -threads "$t" \
    -rate-limit "$rl" \
    -retries "$retries" \
    -timeout "$timeout_secs" \
    -json \
    -irr \
    -output "$json_out" \
    -silent \
    -no-color
}

echo "initial request pass ($(wc -l < urls.txt | tr -d ' ') urls)"
initial_json="$log_dir/pass_0.jsonl"
run_httpx urls.txt "$initial_json" "$threads" "$rate_limit"

# httpx_to_html.rb writes one <pkg>.html file into $output_dir per successful
# response, and prints the input url of every 429 response to stdout, which
# we capture below to build the retry list.
ruby httpx_to_html.rb "$initial_json" "$output_dir" > retry_urls.txt

attempt=1
while [ "$attempt" -le "$max_retries" ]; do
  count=$(wc -l < retry_urls.txt | tr -d ' ')

  if [ "$count" -eq 0 ]; then
    echo "no more 429s, done"
    break
  fi

  delay=$(( base_delay_secs * (2 ** (attempt - 1)) ))
  echo "attempt $attempt: retrying $count url(s) that got 429, backing off ${delay}s first"
  sleep "$delay"

  retry_json="$log_dir/pass_${attempt}.jsonl"
  run_httpx retry_urls.txt "$retry_json" 2 1

  ruby httpx_to_html.rb "$retry_json" "$output_dir" > retry_urls_next.txt
  mv retry_urls_next.txt retry_urls.txt

  attempt=$((attempt + 1))
done

echo "done"
