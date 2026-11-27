This directory contains SamDrucker clients in various languages.

A client needs to:

1. construct the `JSON` data
1. urlencode it
1. perform an HTTP POST to the SamDrucker server

You can use whatever tools you want to create a client.

The scripts and dependencies are listed below:

`samdrucker.sh`

* `/usr/libexec/flua`, from the FreeBSD base system (the `FreeBSD-flua`
  package on pkgbase hosts) - builds the `JSON` payload
* curl - for posting to the web server

Up to 0.3.2, `samdrucker.sh` also needed https://github.com/jpmens/jo.

