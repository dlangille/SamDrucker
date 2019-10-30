-- what packages are installed on this host
-- SELECT * FROM PackagesOnHost('foo.example.org');

CREATE OR REPLACE FUNCTION PackagesOnHost(text) returns SETOF text AS $$
  SELECT P.name || '-' || PV.version
    FROM host H JOIN host_package    HP ON H.name                = $1
                                       AND H.id                  = HP.host_id
                JOIN package_version PV ON HP.package_version_id = PV.id
                JOIN package         P  ON PV.package_id         = P.id
$$ LANGUAGE SQL STABLE;

-- which hosts have this package in this version installed
-- select * from HostsWithPackage('apr', '1.6.5.1.6.1_1');

CREATE OR REPLACE FUNCTION HostsWithPackage(text,text) returns SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                                        AND PV.version = $2
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
$$ LANGUAGE SQL STABLE;


-- which hosts have this package. do not include version
-- select * from HostsWithPackage('apr');

CREATE OR REPLACE FUNCTION HostsWithPackage(text) returns SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
$$ LANGUAGE SQL STABLE;

-- This will be the function which does it all. It takes JSON, and does all the inserts
-- incoming_packages may not be a permanent table.  For now, it's there for having JSON
-- I can work on.

CREATE OR REPLACE FUNCTION HostAddPackages(json) returns INT AS $$
DECLARE
  a_json   ALIAS for $1;

BEGIN
  INSERT INTO incoming_packages (data) values (a_json);
  RETURN 1;
END
$$ LANGUAGE plpgsql;


-- example

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


HostAddPackages() will be extended by using this pseudo code:


-- save the host, get the id

INSERT INTO host (name, os, version, repo) 
   SELECT data->>'name', data->>'os', data->>'version', data->>'repo'
     FROM incoming_packages
    WHERE id = 7
  ON CONFLICT(name) 
  DO UPDATE SET os      = EXCLUDED.os,
                version = EXCLUDED.version,
                repo    = EXCLUDED.repo
  RETURNING id;

 id 
----
  7
(1 row)

INSERT 0 1


hostid=13

for package in $packages
do
  split package into name and version:
    for example: sudo-1.8.28p1
       split on the rightmost hypen.
       Everything to the left is package name.
       Everything to the right is version.

       Try (.+)-[^-]+$

  package='sudo'
  version='1.8.28p1'

  INSERT INTO package (name) values ('sudo')
    ON CONFLICT(name)
    DO NOTHING
    RETURNING id;
 id 
----
  6
(1 row)

INSERT 0 1


  package_id=6

  INSERT INTO package_version (package_id, version) values (6, '1.8.28p1')
    ON CONFLICT ON CONSTRAINT package_version_package_id_version_key
    DO NOTHING
    RETURNING id;
 id 
----
  7
(1 row)

INSERT 0 1

  package_version_id=7

  INSERT INTO host_package (host_id, package_version_id) values(13, 7)
    ON CONFLICT ON CONSTRAINT host_package_host_id_package_version_id_key
    DO NOTHING;

done


