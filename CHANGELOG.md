# Changelog

## host table

Any changes to the `host` table with automatically update the `date_updated`
field. See `update_date_updated` in `PostgreSQL/database-postgresql.sql`.

## 0.3.0

A host can now use more than one pkg repository at once, as it does with
pkgbase: FreeBSD-base for the base system and FreeBSD-ports or a local
repository for everything else. SamDrucker now records every enabled
repository on each host, and which repository each package came from.

The client now also sends:

* `repos` - every enabled repository (`pkg repos -e`), keyed by name
* `package_repos` - the installed packages, grouped by repository

It still sends `repo` as one URL (the first enabled repository), so a
0.3.0 client works with a 0.2.x server. A 0.3.0 server accepts check-ins
from 0.2.x and 0.3.0beta clients too.

The client no longer fails silently. If curl cannot reach the server, the
server replies with an HTTP error, or `samdrucker.php` replies with an error
message (invalid JSON, a database error), the client prints the reason on
stderr, logs it to syslog (tag `samdrucker`, `user.err`), and exits 1, which
the periodic script reports in the daily mail. For this it needs the
server's reply, so it ignores any `--output` in `CURL_OPTIONS`; the sample
configuration no longer has `--output /dev/null`.

The client needs `/usr/libexec/flua` from the base system, and installs
`samdrucker.repo-to-json.stdin` next to `samdrucker.sh`.

A repository is identified by its URL, not its name, because the same name
points at different URLs on different hosts.

New in the database:

* table `repo`: one row per repository URL
* table `host_repo`: each host's enabled repositories, with the name and
  priority that host gives each one
* column `host_package.repo_id`
* functions `ReposOnHost(host)`, `PackagesOnHostShowRepo(host)` and
  `HostsWithPackageShowRepo(package)`; the last also takes a boolean,
  like the other query functions, to list hosts which are not enabled

`host.repo` is still filled in, and the existing query functions return
what they did before.

When upgrading to this release, back up the database, then run these
scripts, in this order, as the owner of the tables. If you are upgrading
from a release before 0.2.4, run `PostgreSQL/updates-2020.08.28.sql` first.

* `PostgreSQL/updates-2026.11.19.sql`
* `PostgreSQL/procedures.sql`

Upgrade the server before the clients. A 0.2.x server ignores what is new
in a 0.3.0 check-in, so nothing breaks if a client is upgraded first; the
repositories are just not recorded until the server is upgraded.

## 0.2.4

With this release, you can set a host to be not enabled. Perhaps you have a
host which is no longer in use but you want to keep the data.

When upgrading to this release, be sure to run these scripts:

* `PostgreSQL/updates-2020.08.28.sql`
* `PostgreSQL/procedures.sql`

If you want to disable any hosts, this SQL will work:

```
update host set enabled = false where name in ('foo', 'bar');
```

New versions of the query functions have been created. These take a boolean
parameter as their last arguement. This allows you to query hosts which are
no longer enabled (false). The existing functions will now only query
enabled hosts. You can retain existing behaviour by leaving all hosts
enabled.
