#!/bin/sh

# we want to construct JSON which looks like this:
# {
#   "name": "test.example.org",
#   "os": "FreeBSD",
#   "version": "11.3-RELEASE-p4",
#   "repo": "http://pkg.freebsd.org/FreeBSD:113:amd64/latest/",
#   "packages": [
#       "apr-1.6.5.1.6.1_1",
#       "bacula9-client-9.4.3",
#       "bash-5.0.7",
#       "rsync-3.1.3_1",
#       "serf-1.3.9_3",
#       "sqlite3-3.29.0_1"
#    ]
# }
#
# I am using the FreeBSD textproc/jo:
#
# $ jo -p name=`hostname` os=`uname` version=`uname -r` repo=`pkg -vv | grep ' url' | cut -f2 -d \"`
# {
#    "name": "samdrucker.int.unixathome.org",
#    "os": "FreeBSD",
#    "version": "12.0-RELEASE-p10",
#    "repo": "pkg+http://fedex.unixathome.org/packages/120amd64-default-master-list/"
# }
#

if [ -r /usr/local/etc/samdrucker/samdrucker-dev.conf ]; then
  . /usr/local/etc/samdrucker/samdrucker-dev.conf
fi

CURL="/usr/local/bin/curl"
CUT="/usr/bin/cut"
GREP="/usr/bin/grep"
JO="/usr/local/bin/jo"
PKG="/usr/sbin/pkg"
REPO2JSON="/usr/local/bin/samdrucker.repo-to-json.stdin"

# get list of packages on this host:

pkg_args=""
PKGS=`$PKG info -q`
for pkg in $PKGS
do
  pkg_args="$pkg_args packages[]=$pkg"
done

hostname=$(/bin/hostname)
uname=$(/usr/bin/uname)
version=$(/bin/freebsd-version)

repo_args=$(pkg repositories | ${samdrucker.repo-to-json.stdin})

# we save this to a file to avoid potential command line arguement overflow
payload=$(mktemp /tmp/SamDrucker.payload.XXXXXX)

$JO -p name=$hostname os=$uname version=$version repo="$repo_args" packages=$($JO -a $($PKG info -q | sort)) > $payload

$CURL $CURL_OPTIONS --data-urlencode ${SAMDRUCKER_ARG}@${payload} $SAMDRUCKER_URL

# remove the temp file
rm $payload
