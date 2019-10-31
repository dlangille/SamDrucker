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


CREATE OR REPLACE FUNCTION HostAddPackages(json) returns INT AS $$
DECLARE
  a_json   ALIAS for $1;

  l_incoming_packages_id integer;  
  l_host_id              integer;
  l_package              text;
  l_package_name         text;
  l_package_version      text;
  l_package_id           integer;
  l_package_version_id   integer;

BEGIN
-- save the data, just because we can
    INSERT INTO incoming_packages (data) values (a_json)
    RETURNING id
    INTO l_incoming_packages_id;

-- save the host, get the id

  INSERT INTO host (name, os, version, repo) 
    SELECT a_json->>'name', a_json->>'os', a_json->>'version', a_json->>'repo'
    ON CONFLICT(name) 
    DO UPDATE SET os      = EXCLUDED.os,
                  version = EXCLUDED.version,
                  repo    = EXCLUDED.repo
    RETURNING id
    INTO l_host_id;

-- for package in $packages

  FOR l_package IN SELECT * FROM json_array_elements_text(a_json->'packages')
  LOOP
--  split package into name and version:
--  for example: sudo-1.8.28p1
--     split on the rightmost hypen.
--     Everything to the left is package name.
--     Everything to the right is version.

    SELECT substring(l_package, '(.+)-[^-]+$')
    INTO l_package_name;

    SELECT substring(l_package, '.+-([^-]+)$')
    INTO l_package_version;

    INSERT INTO package (name) values (l_package_name)
      ON CONFLICT(name)
      DO UPDATE SET name = EXCLUDED.name
      RETURNING id
      INTO l_package_id;

    INSERT INTO package_version (package_id, version) values (l_package_id, l_package_version)
      ON CONFLICT ON CONSTRAINT package_version_package_id_version_key
      DO UPDATE SET version = EXCLUDED.version
      RETURNING id
      INTO l_package_version_id;

    INSERT INTO host_package (host_id, package_version_id) values(l_host_id, l_package_version_id)
      ON CONFLICT ON CONSTRAINT host_package_host_id_package_version_id_key
      DO NOTHING;

  END LOOP;
    
  RETURN l_incoming_packages_id;
END
$$ LANGUAGE plpgsql;
