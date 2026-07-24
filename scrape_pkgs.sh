#!/usr/bin/env bash
set -euo pipefail

echo "scraping cran pkg check pages"

url='https://crandb.r-pkg.org/-/pkgnames'
url_pat='https://cloud.r-project.org/web/checks/check_results_%s.html\n'
output_dir='/tmp/htmls'
log_file='/tmp/ganda.log'

# Root cause of the 429s: ganda's Go http.Client sends the default User-Agent
# "Go-http-client/2.0" when none is set, and CloudFront's WAF in front of
# cloud.r-project.org specifically throttles that UA (confirmed via a 429
# response carrying "x-ratelimit-limit: 100" and "retry-after: 300"). Plain
# curl (a normal browser-ish UA) was not throttled at all, even at 1000+
# concurrent distinct-URL requests. So the real fix is to send a real UA.
user_agent='cchecksbadges-scraper/1.0 (+https://github.com/sckott/cchecksbadges)'

# ganda's own --retry/--base-retry-millis backoff only applies to 5XX errors
# and timeouts, not 429 (Too Many Requests) - see requests/requests.go in the
# ganda source, which treats any status < 500 as "don't retry". With the UA
# fix above we shouldn't see 429s anymore, but we keep a throttle and a retry
# loop as a safety net. If we ever do get 429'd again, CloudFront told us it
# wants a 300s (5 minute) cooldown, so the retry loop backs off starting from
# that value rather than guessing.
workers=15
throttle_per_second=10
max_retries=3
base_delay_secs=300

# optional: set LIMIT=2000 (or any number) in the environment to only scrape
# the first N package names, useful for testing before a full run
limit="${LIMIT:-0}"

mkdir -p "$output_dir"

curl "$url" > names.json
jq -r '. | keys[]' names.json > names.txt

if [ "$limit" -gt 0 ]; then
  echo "LIMIT set, only scraping first $limit package names"
  head -n "$limit" names.txt > names_subset.txt
  mv names_subset.txt names.txt
fi

xargs printf "$url_pat" < names.txt > urls.txt

echo "initial request pass ($(wc -l < urls.txt | tr -d ' ') urls)"
ganda \
  --connect-timeout-millis 10000 \
  --workers "$workers" \
  --throttle-per-second "$throttle_per_second" \
  --header "User-Agent: $user_agent" \
  --retry 5 \
  --base-retry-millis 2000 \
  --output-directory "$output_dir" \
  < urls.txt 2>&1 | tee "$log_file"

attempt=1
while [ "$attempt" -le "$max_retries" ]; do
  grep '^Response: 429 ' "$log_file" | awk '{print $3}' | sort -u > retry_urls.txt || true
  count=$(wc -l < retry_urls.txt | tr -d ' ')

  if [ "$count" -eq 0 ]; then
    echo "no more 429s, done"
    break
  fi

  delay=$(( base_delay_secs * (2 ** (attempt - 1)) ))
  echo "attempt $attempt: retrying $count url(s) that got 429, backing off ${delay}s first"
  sleep "$delay"

  ganda \
    --connect-timeout-millis 10000 \
    --workers 2 \
    --throttle-per-second 1 \
    --header "User-Agent: $user_agent" \
    --retry 5 \
    --base-retry-millis 2000 \
    --output-directory "$output_dir" \
    < retry_urls.txt 2>&1 | tee "$log_file"

  attempt=$((attempt + 1))
done

echo "done"
