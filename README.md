# What is Sam Drucker?

SamDrucker is a collection of small components which create a centralized
list of all packages on all hosts

Each components is designed to be:

* small
* simple
* easily written
* flexiable
* few, if any, dependencies

## The components

* client - collects the list of packages and posts it to the server
* server - accepts the list of packages and adds it to the database
* database - tables and stored procedures for the catalog of packages

Each component can be written in whatever languages you want. Collect
the packages in any manner you want. This can be done remotely on the host
or centrally on a management tool, such as Ansible.

Pick whatever languages you want.

## Other ideas

It was mentioned elsewhere that Ansible or Spacewalk can help here. I want
something completely independent. These tools are great at collecting information.

I didn't want to use a large number of dependencies or huge packages.

## Current status

A sample client and web service have been created as proof of concept.
They are deployed in my home network, active on about 90 hosts.

A database schema has been created for PostgreSQL, my database of personal
choice, but this should work on any other database. Patches welcome here.

## Next major step

At present, queries of the database are possible only via command line tools

I'd like to create a simple web interface.

Anyone is weclome to help write this stuff.

## JSON

This is sample JSON which would be pushed to the service

```
{
  "name": "foo.example.org",
  "os": "FreeBSD",
  "version": "12.0-RELEASE-p8",
  "repo": "http://pkg.freebsd.org/FreeBSD:12:amd64/latest/",
  "packages": {
    "package": [
      "apr-1.6.5.1.6.1_1",
      [
        "bacula9-client-9.4.3"
      ],
      [
        "bash-5.0.7"
      ]
    ]
  }
}
```

## Database tables

These are the proposed database tables and corresponding queries.

### host

```
id
name
os
version
repo
```

### package

```
id
name (e.g. foo)
```

### package_version

```
id
package_id
version (e.g. 1.2.3)
````

### host_package

```
host_id
package_version_id
````

## Sample queries

Show me hosts with `foo-1.2.3` installed.

```
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = 'foo' 
                                        AND P.id       = PV.package_id
                                        AND PV.version = '1.2.3'
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
  ORDER BY 1;
```

Show me all packages installed on host `bar`

```
SELECT P.name || '-' || PV.version
  FROM host H JOIN host_package    HP ON H.name                = 'bar'
                                     AND H.id                  = HP.host_id
              JOIN package_version PV ON HP.package_version_id = PV.id
              JOIN package         P  ON HP.package_id         = P.id
  ORDER BY 1;
```

## Query with functions

There will be functions you can use instead of the SQL. Functions are the
recommend access method.


Where is `apr` installed?

```
# select * from HostsWithPackage('apr');
 hostswithpackage 
------------------
 foo.example.org
(1 row)
```

What is installed on `foo`?

```
samdrucker=# SELECT * FROM PackagesOnHost('foo.example.org');
    packagesonhost    
----------------------
 apr-1.6.5.1.6.1_1
 bacula9-client-9.4.3
(2 rows)
```

This is how inserts and updates will be done:

```
SELECT HostAddPackages('{
  "name": "foo.example.org",
  "os": "FreeBSD",
  "version": "12.0-RELEASE-p8",
  "repo": "http://pkg.freebsd.org/FreeBSD:12:amd64/latest/",
  "packages": {
    "package": [
      "apr-1.6.5.1.6.1_1",
      [
        "bacula9-client-9.4.3"
      ],
      [
        "bash-5.0.7"
      ]
    ]
  }
}');
```
