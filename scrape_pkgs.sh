echo "scraping cran pkg check pages"
url='https://crandb.r-pkg.org/-/pkgnames'
url_pat='https://cran.rstudio.com/web/checks/check_results_%s.html\n'
curl $url > names.json
cat names.json | jq '. | keys[]' > names.txt
cat names.txt | xargs printf $url_pat | ganda --connect-timeout 10 --workers 40 -o /tmp/htmls
echo "done"
