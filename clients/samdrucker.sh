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
FLUA="/usr/libexec/flua"
LOGGER="/usr/bin/logger"
PKG="/usr/sbin/pkg"
SED="/usr/bin/sed"
TAIL="/usr/bin/tail"
TR="/usr/bin/tr"

# Lua for flua: builds the whole JSON payload described above and writes
# it to stdout. It runs `pkg repos -e` and `pkg query` itself. It is
# passed with -e; the shell hands it the values it needs in the
# environment. Up to 0.3.2 the payload was built with jo(1).
PAYLOAD_LUA='
local ucl = require("ucl")
local pkg = os.getenv("PKG")

local function die(msg)
  io.stderr:write(msg .. "\n")
  os.exit(1)
end

-- run a command, return everything it printed; give up if it fails
local function run(cmd)
  local f = io.popen(cmd)
  local out = f:read("a")
  local ok, how, code = f:close()
  if not ok then
    die(cmd .. " failed (" .. how .. " " .. tostring(code) .. ")")
  end
  return out
end

-- ucl writes an empty Lua table as [], but repos and package_repos are
-- objects; this metatable makes ucl write them as {} even when empty
local object = { class = "ucl.type.object" }

-- The enabled repositories, as pkg prints them.
local repos_ucl = run(pkg .. " repos -e")

-- For 0.2.x servers: the URL of the first enabled repository. Read it
-- from the text, which is in pkg order; the parsed table has no order.
local repo = ""
for line in repos_ucl:gmatch("[^\n]+") do
  local url = line:match("^%s+url%s*:%s*\"([^\"]*)\"")
  if url then
    repo = url
    break
  end
end

-- All enabled repositories, converted from UCL.
local repos = setmetatable({}, object)
if repos_ucl:match("%S") then
  local parser = ucl.parser()
  local ok, err = parser:parse_string(repos_ucl)
  if not ok then
    die("cannot parse the output of pkg repos -e: " .. err)
  end
  repos = setmetatable(parser:get_object(), object)
end

-- The installed packages, and the same packages grouped by the
-- repository each came from, from one pkg query.
local packages, package_repos = {}, setmetatable({}, object)
for r, p in run(pkg .. " query \"%R\t%n-%v\""):gmatch("([^\t\n]*)\t([^\n]*)") do
  packages[#packages + 1] = p
  package_repos[r] = package_repos[r] or {}
  table.insert(package_repos[r], p)
end
table.sort(packages)
for _, list in pairs(package_repos) do
  table.sort(list)
end

-- Pretty-printed: samdrucker.php stores the payload as sent, and this
-- keeps it readable in the database. The keys come out in no set order.
print(ucl.to_format({
  name          = os.getenv("SAMDRUCKER_NAME"),
  os            = os.getenv("SAMDRUCKER_OS"),
  version       = os.getenv("SAMDRUCKER_VERSION"),
  repo          = repo,
  repos         = repos,
  packages      = packages,
  package_repos = package_repos,
}, "json"))
'

hostname=$(/bin/hostname)
uname=$(/usr/bin/uname)
version=$(/bin/freebsd-version)

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

lua_errors=$( { SAMDRUCKER_NAME="$hostname" SAMDRUCKER_OS="$uname" \
                SAMDRUCKER_VERSION="$version" PKG="$PKG" \
                $FLUA -e "$PAYLOAD_LUA" > "$payload"; } 2>&1 ) \
  || fail "flua failed to build the JSON payload: $lua_errors"

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
