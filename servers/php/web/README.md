# SamDrucker reporting website

A read-only website for browsing what SamDrucker has collected:

* **Hosts** (`index.php`): every host, its OS version, when it last checked
  in, how many packages it has, and its repositories. Hosts which have not
  checked in for 25 hours are marked *stale*.
* **Host** (`host.php?name=`): one host's repositories and every installed
  package, with the repository each came from.
* **Package** (`package.php?name=`): which hosts have a package, in which
  version and from which repository, with a count of hosts per version.
* **Packages** (`packages.php?q=`): find packages by part of their name.
* **Repositories** (`repos.php`): every repository URL in use, the names
  hosts give it, and which hosts use it.

Pages showing hosts can include disabled hosts with `all=1`.

## Downloading results

Every result table has **Download: CSV JSON** links. They fetch the same
page with `format=csv` or `format=json` added, so the file holds exactly
the rows on the page, with the same search and `all=1` setting. Files are
named after the page and the UTC time, for example
`hosts-with-php85-20261120T153000Z.csv`.

In CSV, a value starting with `=`, `+`, `-`, `@`, tab or carriage return
gets a leading `'`, so a spreadsheet shows it as text instead of running it
as a formula. JSON is never changed.

## Requirements

* PHP 8.1 or later, with `pdo_pgsql`
* the 0.3.0 database schema and `PostgreSQL/procedures.sql`
* `PostgreSQL/updates-website.sql`, which lets the reporting role read
  the package tables

## Installing

1. Run `PostgreSQL/updates-website.sql`, and create a login in the
   `reporting` role if you do not have one (see that file).
1. Allow that login from the web server in `pg_hba.conf`.
1. Copy `include/` and `www/` side by side, for example to
   `/usr/local/www/samdrucker/web/`.
1. Copy `samdruckerweb.conf.sample` to
   `/usr/local/etc/samdrucker/samdruckerweb.conf`, fill it in, and make it
   readable only by the user php-fpm runs as.
1. Point nginx at `www/`; see `nginx-config.conf`.

## Keep it private

The website lists the exact package versions on every host, which is a map
of what each host is vulnerable to. Serve it on an internal name only,
restrict it to your own networks, and add a password if needed. It sends
`noindex` to search engines, but that is no substitute for access control.

The website only reads. It connects as a member of the `reporting` role,
which has `SELECT` and nothing else, and sets its session read-only too.
