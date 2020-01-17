-- what packages are installed on this host
-- SELECT * FROM PackagesOnHost('foo.example.org');

CREATE OR REPLACE FUNCTION PackagesOnHost(text) RETURNS SETOF text AS $$
  SELECT P.name || '-' || PV.version
    FROM host H JOIN host_package    HP ON H.name                = $1
                                       AND H.id                  = HP.host_id
                JOIN package_version PV ON HP.package_version_id = PV.id
                JOIN package         P  ON PV.package_id         = P.id
$$ LANGUAGE SQL STABLE;

-- which hosts have this package in this version installed
-- select * from HostsWithPackage('apr', '1.6.5.1.6.1_1');

CREATE OR REPLACE FUNCTION HostsWithPackage(text,text) RETURNS SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                                        AND PV.version = $2
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
$$ LANGUAGE SQL STABLE;


-- which hosts have this package. do not include version
-- select * from HostsWithPackage('apr');

CREATE OR REPLACE FUNCTION HostsWithPackage(text) RETURNS SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
$$ LANGUAGE SQL STABLE;

-- which hosts have this package. do not include version
-- select * from HostsWithPackage('apr');

CREATE OR REPLACE FUNCTION HostsWithPackageShowVersion(text)
  RETURNS TABLE(host text, package_version text) AS $$
SELECT H.name, P.name || '-' || PV.version
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id
$$ LANGUAGE SQL STABLE;

-- This will be the function which does it all. It takes JSON, and does all the inserts
-- incoming_packages may not be a permanent table.  For now, it's there for having JSON
-- I can work on.

CREATE OR REPLACE FUNCTION HostAddPackages(a_json json, a_client_ip cidr) RETURNS INT AS $$
DECLARE
  l_query  text;
  l_id     integer;
BEGIN
  l_query := 'INSERT INTO incoming_packages (data, client_ip) values ($1, $2) RETURNING id';
  EXECUTE l_query
    INTO l_id
    USING a_json, a_client_ip;

  RETURN l_id;
END
$$ LANGUAGE plpgsql;


-- example

SELECT HostAddPackages('{
  "name": "foo.example.org",
  "os": "FreeBSD",
  "version": "12.0-RELEASE-p8",
  "repo": "http://pkg.freebsd.org/FreeBSD:12:amd64/latest/",
  "packages": [
      "apr-1.6.5.1.6.1_1",
        "bacula9-client-9.4.3",
        "bash-5.0.7"
  ]
}', '198.51.100.0');


HostAddPackages() will be extended by using this pseudo code:


CREATE OR REPLACE FUNCTION HostAddPackages(a_json json, a_client_ip cidr) RETURNS INT AS $$
DECLARE
  l_query                text;
  l_incoming_packages_id integer;
  l_host_id              integer;
  l_package              text;
  l_package_name         text;
  l_package_version      text;
  l_package_id           integer;
  l_package_version_id   integer;

BEGIN
-- save the data, just because we can
  l_query := 'INSERT INTO incoming_packages (data, client_ip) values ($1, $2) RETURNING id';
  EXECUTE l_query
    INTO l_incoming_packages_id
    USING a_json, a_client_ip;

-- save the host, get the id

  l_query := 'INSERT INTO host (name, os, version, repo) 
               SELECT $1, $2, $3, $4
               ON CONFLICT(name) 
               DO UPDATE SET os      = EXCLUDED.os,
                             version = EXCLUDED.version,
                             repo    = EXCLUDED.repo
               RETURNING id';

  EXECUTE l_query
    INTO l_host_id
    USING a_json->>'name', a_json->>'os', a_json->>'version', a_json->>'repo';
    
-- delete existing packages for this host

  DELETE FROM host_package
    WHERE host_id = l_host_id;

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

    l_query := 'INSERT INTO package (name) values ($1)
                 ON CONFLICT(name)
                 DO UPDATE SET name = EXCLUDED.name
                 RETURNING id';

    EXECUTE l_query
      INTO l_package_id
      USING l_package_name;

    l_query := 'INSERT INTO package_version (package_id, version) values ($1, $2)
                  ON CONFLICT ON CONSTRAINT package_version_package_id_version_key
                  DO UPDATE SET version = EXCLUDED.version
                  RETURNING id';

    EXECUTE l_query
       INTO l_package_version_id
      USING l_package_id, l_package_version;

    l_query := 'INSERT INTO host_package (host_id, package_version_id) values($1, $2)
                   ON CONFLICT ON CONSTRAINT host_package_host_id_package_version_id_key
                   DO NOTHING';

    EXECUTE l_query
      USING l_host_id, l_package_version_id;

  END LOOP;
    
  RETURN l_incoming_packages_id;
END
$$ LANGUAGE plpgsql;
