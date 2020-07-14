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
# $ jo -p name=`hostname` os=`uname` version=`uname -r` repo=`pkg -vv | grep url | cut -f2 -d \"`
# {
#    "name": "samdrucker.int.unixathome.org",
#    "os": "FreeBSD",
#    "version": "12.0-RELEASE-p10",
#    "repo": "pkg+http://fedex.unixathome.org/packages/120amd64-default-master-list/"
# }
#

if [ -r /usr/local/etc/samdrucker/samdrucker.conf ]; then
  . /usr/local/etc/samdrucker/samdrucker.conf
fi

CURL="/usr/local/bin/curl"
CUT="/usr/bin/cut"
GREP="/usr/bin/grep"
JO="/usr/local/bin/jo"
PKG="/usr/sbin/pkg"

# get list of packages on this host:

pkg_args=""
PKGS=`$PKG info -q`
for pkg in $PKGS
do
  pkg_args="$pkg_args packages[]=$pkg"
done

hostname=`hostname`
uname=`uname`
version=`uname -r`
repo=`/usr/sbin/pkg -vv | $GREP  url | $CUT -f2 -d \"`

# we save this to a file to avoid potential command line arguement overflow
payload=$(mktemp /tmp/SamDrucker.payload.XXXXXX)
$JO -p name=$hostname os=$uname version=$version repo=$repo $pkg_args > $payload

$CURL $CURL_OPTIONS --data-urlencode ${SAMDRUCKER_ARG}@${payload} $SAMDRUCKER_URL
