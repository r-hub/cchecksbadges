# cchecksbadges

CRAN checks Badges

Just the badges from https://github.com/sckott/cchecksapi - no API - just the badges

The workflow is easiest to see in the [GitHub Actions workflow file](https://github.com/sckott/cchecksbadges/blob/main/.github/workflows/badges.yml). The high level steps to make the badges (titled by the name's in the workflow file):

1. Gather CRAN data: Using the Go based tool [ganda][] via a shell script (`scrape_pkgs.sh`), download html files for CRAN checks pages for all packages on CRAN.
2. Scrape html: Using Ruby (`scrape.rb`), parse each html file, pulling out the required pieces of data, writing the data to a json file for each package.
3. Make svgs: Using Ruby again (`badges.rb`, `badge_methods.rb`), for each package, read its json file and make svgs for each route below and write those to disk
4. Deploy: using a 3rd party github action, push all svg files in svgs/badges to the [gh-pages branch](https://github.com/sckott/cchecksbadges/tree/gh-pages)

After deploy to gh-pages, Netlify will kick off a build and the site will be served from Netlify.

Notes: 

- The workflow file has the term `rake` - this is similar to `make`, but specific to Ruby. The commands are defined in the Rakefile (similar to make's Makefile).
- Dependencies are defined in file `Gemfile`
- The Ruby version is defined in the file `.ruby-version`

## Routes

- `/summary/:pkg.svg`
- `/worst/:pkg.svg`
- `/flavor/windows/:pkg.svg`
- `/flavor/linux/:pkg.svg`
- `/flavor/macos/:pkg.svg`
- `/flavor/solaris/:pkg.svg`
- `/flavor/devel/:pkg.svg`
- `/flavor/release/:pkg.svg`
- `/flavor/r-devel-linux-x86_64-debian-clang/:pkg.svg`
- `/flavor/r-devel-linux-x86_64-debian-gcc/:pkg.svg`
- `/flavor/r-devel-linux-x86_64-fedora-clang/:pkg.svg`
- `/flavor/r-devel-linux-x86_64-fedora-gcc/:pkg.svg`
- `/flavor/r-devel-windows-ix86+x86_64/:pkg.svg`
- `/flavor/r-oldrel-macos-x86_64/:pkg.svg`
- `/flavor/r-oldrel-windows-ix86+x86_64/:pkg.svg`
- `/flavor/r-patched-linux-x86_64/:pkg.svg`
- `/flavor/r-release-linux-x86_64/:pkg.svg`
- `/flavor/r-release-macos-x86_64/:pkg.svg`
- `/flavor/r-release-windows-ix86+x86_64/:pkg.svg`

## Some example routes

- https://badges.cranchecks.info/summary/taxize.svg
- https://badges.cranchecks.info/worst/dplyr.svg
- https://badges.cranchecks.info/flavor/r-devel-linux-x86_64-fedora-clang/DT.svg


[ganda]: https://github.com/tednaleid/ganda
