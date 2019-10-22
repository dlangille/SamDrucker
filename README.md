# What is Sam Drucker?

I have posted about this in the past. I feel very motivated
to have a centralized list of what packages are installed on each host.

I know I can query the hosts, but having it centrally located means I can
'instantly' identify all the hosts which have foo-1.03 installed.

It was mentioned elsewhere that Ansible or Spacewalk can help here. I want
something completely independent.

You could get those tools to push the results to the web service.

This repo is the start of that work.

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
                 JOIN host         H     ON PV.host_id = H.id
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
