#!/bin/sh

# Send this host's package list to a SamDrucker server.
#
# We construct JSON which looks like this:
# {
#   "name": "test.example.org",
#   "os": "FreeBSD",
#   "version": "15.1-RELEASE-p7",
#   "repo": "http://pkg.example.org/FreeBSD:15:amd64/base_release_1",
#   "repos": {
#     "FreeBSD-base": {
#       "url": "http://pkg.example.org/FreeBSD:15:amd64/base_release_1",
#       "enabled": true,
#       "priority": 0,
#       ...
#     },
#     "local": { "url": "http://pkg.example.org/FreeBSD:15:amd64", ... }
#   },
#   "packages": [
#     "FreeBSD-acct-15.1p4",
#     "bash-5.3.3",
#     "php85-8.5.0"
#   ],
#   "package_repos": {
#     "FreeBSD-base": [ "FreeBSD-acct-15.1p4" ],
#     "local":        [ "bash-5.3.3", "php85-8.5.0" ]
#   }
# }
#
# name, os, version, repo and packages are what SamDrucker 0.2.x sends, and
# all a 0.2.x server reads. repo is the URL of the first enabled repository.
#
# repos and package_repos are new in 0.3.0. With pkgbase a host uses several
# repositories at once; repos lists every enabled one (`pkg repos -e`), and
# package_repos says which repository each installed package came from.
# A 0.2.x server ignores both keys, so this client works with old servers too.
#
# Packages not installed from any repository (for example, with
# `pkg add` of a local file) are listed under "unknown-repository".

if [ -r /usr/local/etc/samdrucker/samdrucker.conf ]; then
  . /usr/local/etc/samdrucker/samdrucker.conf
fi

CURL="/usr/local/bin/curl"
CUT="/usr/bin/cut"
GREP="/usr/bin/grep"
HEAD="/usr/bin/head"
JO="/usr/local/bin/jo"
LOGGER="/usr/bin/logger"
PKG="/usr/sbin/pkg"
SED="/usr/bin/sed"
SORT="/usr/bin/sort"
TAIL="/usr/bin/tail"
TR="/usr/bin/tr"
FLUA="/usr/libexec/flua"

# Lua for flua: converts the UCL printed by `pkg repos` into JSON. It is
# passed with -e, so stdin stays free for the data. Up to 0.3.0 this
# was a separate script, samdrucker.repo-to-json.stdin (obtained from dch).
REPO2JSON_LUA='
local ucl = require("ucl")
local parser = ucl.parser()
local ok, err = parser:parse_string(io.stdin:read("*all"))
if not ok then
  io.stderr:write("Error parsing UCL: " .. err .. "\n")
  os.exit(1)
end
print(ucl.to_format(parser:get_object(), "json"))
'

hostname=$(/bin/hostname)
uname=$(/usr/bin/uname)
version=$(/bin/freebsd-version)

# The enabled repositories, as pkg prints them.
repos_ucl=$($PKG repos -e)

# For 0.2.x servers: the URL of the first enabled repository.
repo=$(echo "$repos_ucl" | $GREP ' url ' | $HEAD -1 | $CUT -f2 -d \")

# All enabled repositories, converted to JSON.
repos=$(echo "$repos_ucl" | $FLUA -e "$REPO2JSON_LUA")
if [ -z "$repos" ]; then
  repos='{}'
fi

# The installed packages, grouped by the repository each came from.
package_repos_args=""
for r in $($PKG query '%R' | $SORT -u)
do
  package_repos_args="$package_repos_args $r=$($JO -a $($PKG query '%R %n-%v' | while read pr pv; do [ "$pr" = "$r" ] && echo "$pv"; done | $SORT))"
done
package_repos=$($JO $package_repos_args)

# Report a failure: to stderr, which periodic(8) includes in the daily
# mail, and to syslog. Then remove the payload and exit non-zero, so the
# periodic script reports that something went wrong.
fail() {
  echo "samdrucker.sh: $*" >&2
  $LOGGER -t samdrucker -p user.err -- "$*"
  [ -n "$payload" ] && rm -f "$payload"
  exit 1
}

# we save this to a file; curl reads it from there
payload=$(mktemp /tmp/SamDrucker.payload.XXXXXX) || fail "cannot create a temporary file"

$JO -p name="$hostname" os="$uname" version="$version" repo="$repo" \
       repos="$repos" \
       packages="$($JO -a $($PKG info -q | $SORT))" \
       package_repos="$package_repos" > $payload || fail "jo failed to build the JSON payload"

# Before 0.3.0 the sample configuration had "--output /dev/null" in
# CURL_OPTIONS, which threw away the server's reply. We need the reply to
# know whether the check-in worked, so drop that option if it is there.
curl_options=$(echo "$CURL_OPTIONS" | $SED -E 's/(^|[[:space:]])(--output|-o)[[:space:]]+[^[:space:]]+//g')

# --write-out appends the HTTP status code as a last line of its own.
# --show-error keeps curl's own error message, even with --silent.
reply=$($CURL $curl_options --show-error --write-out '\n%{http_code}' \
              --data-urlencode ${SAMDRUCKER_ARG}@${payload} $SAMDRUCKER_URL 2>&1)
curl_rc=$?

http_code=$(echo "$reply" | $TAIL -n 1)
# the reply without the status line, as one line, at most 300 characters
body=$(echo "$reply" | $SED '$d' | $TR -s '[:space:]' ' ' | $CUT -c 1-300)
body=${body# }
body=${body% }

if [ $curl_rc -ne 0 ]; then
  fail "curl could not post to $SAMDRUCKER_URL (exit $curl_rc): $body"
fi

# samdrucker.php replies with an empty body when it stores the check-in,
# and prints a message when the JSON is invalid or the database fails,
# still with HTTP 200.
case "$http_code" in
2??)
  if [ -n "$body" ]; then
    fail "$SAMDRUCKER_URL did not store the check-in (HTTP $http_code): $body"
  fi
  ;;
*)
  fail "$SAMDRUCKER_URL refused the check-in (HTTP $http_code): $body"
  ;;
esac

# remove the temp file
rm $payload
