-- what packages are installed on this host
-- SELECT * FROM PackagesOnHost('foo.example.org');

CREATE OR REPLACE FUNCTION PackagesOnHost(text,boolean) RETURNS SETOF text AS $$
  SELECT P.name || '-' || PV.version
    FROM host H JOIN host_package    HP ON H.name                = $1 AND H.enabled = $2
                                       AND H.id                  = HP.host_id
                JOIN package_version PV ON HP.package_version_id = PV.id
                JOIN package         P  ON PV.package_id         = P.id
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION PackagesOnHost(text) RETURNS SETOF text AS $$
  SELECT * FROM PackagesOnHost($1, true);
$$ LANGUAGE SQL STABLE;

-- which hosts have this package in this version installed
-- select * from HostsWithPackage('apr', '1.6.5.1.6.1_1');

CREATE OR REPLACE FUNCTION HostsWithPackage(text,text,boolean) RETURNS SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                                        AND PV.version = $2
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id AND H.enabled = $3
$$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION HostsWithPackage(text,text) RETURNS SETOF text AS $$
SELECT * FROM HostsWithPackage($1, $2, true)
$$ LANGUAGE SQL STABLE;


-- which hosts have this package. do not include version
-- select * from HostsWithPackage('apr');

CREATE OR REPLACE FUNCTION HostsWithPackage(text,boolean) RETURNS SETOF text AS $$
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id AND H.enabled = $2
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION HostsWithPackage(text) RETURNS SETOF text AS $$
SELECT * FROM HostsWithPackage($1, true)
$$ LANGUAGE SQL STABLE;

-- which hosts have this package. do not include version
-- select * from HostsWithPackage('apr');

CREATE OR REPLACE FUNCTION HostsWithPackageShowVersion(text,boolean)
  RETURNS TABLE(host text, package_version text) AS $$
SELECT H.name, P.name || '-' || PV.version
  FROM package P JOIN package_version PV ON P.name     = $1
                                        AND P.id       = PV.package_id
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON HP.host_id = H.id  AND H.enabled = $2
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION HostsWithPackageShowVersion(text)
  RETURNS TABLE(host text, package_version text) AS $$
SELECT * FROM HostsWithPackageShowVersion($1, true)
$$ LANGUAGE SQL STABLE;

-- which enabled repositories does this host use
-- SELECT * FROM ReposOnHost('foo.example.org');
-- name is NULL for hosts running a 0.2.x client, which sends only a URL.

CREATE OR REPLACE FUNCTION ReposOnHost(text)
  RETURNS TABLE(name text, url text, priority int) AS $$
SELECT HR.name, R.url, HR.priority
  FROM host H JOIN host_repo HR ON H.name = $1
                               AND H.id   = HR.host_id
              JOIN repo      R  ON HR.repo_id = R.id
 ORDER BY HR.name, R.url
$$ LANGUAGE SQL STABLE;

-- what packages are installed on this host, and from which repository
-- SELECT * FROM PackagesOnHostShowRepo('foo.example.org');
-- repo_name and url are NULL when the repository is not known: a 0.2.x
-- client, a package added from a file, or a repository since disabled.

CREATE OR REPLACE FUNCTION PackagesOnHostShowRepo(text)
  RETURNS TABLE(package_version text, repo_name text, url text) AS $$
SELECT P.name || '-' || PV.version, HR.name, R.url
  FROM host H JOIN host_package    HP ON H.name                = $1
                                     AND H.id                  = HP.host_id
              JOIN package_version PV ON HP.package_version_id = PV.id
              JOIN package         P  ON PV.package_id         = P.id
         LEFT JOIN repo            R  ON HP.repo_id            = R.id
         LEFT JOIN host_repo       HR ON HR.host_id            = HP.host_id
                                     AND HR.repo_id            = HP.repo_id
 ORDER BY 1
$$ LANGUAGE SQL STABLE;


-- HostAddPackages() takes one check-in from a client and replaces
-- everything recorded for that host.
--
-- It accepts what every client version sends:
--
--   0.2.x      "repo" is one URL, as a string
--   0.3.0beta  "repo" is the output of `pkg repositories`, as an object
--              keyed by repository name, disabled repositories included
--   0.3.0      "repo" is one URL, as a string, for 0.2.x servers;
--              "repos" is `pkg repos -e` as an object keyed by name, and
--              "package_repos" maps each repository name to the packages
--              installed from it
--
-- example, as sent by a 0.3.0 client:
--
-- SELECT HostAddPackages('{
--   "name": "foo.example.org",
--   "os": "FreeBSD",
--   "version": "15.1-RELEASE-p7",
--   "repo": "http://pkg.example.org/FreeBSD:15:amd64/base_release_1",
--   "repos": {
--     "FreeBSD-base": { "url": "http://pkg.example.org/FreeBSD:15:amd64/base_release_1",
--                       "enabled": true, "priority": 0 },
--     "local":        { "url": "http://pkg.example.org/FreeBSD:15:amd64",
--                       "enabled": true, "priority": 0 }
--   },
--   "packages": [
--     "FreeBSD-acct-15.1p4",
--     "bash-5.3.3"
--   ],
--   "package_repos": {
--     "FreeBSD-base": [ "FreeBSD-acct-15.1p4" ],
--     "local":        [ "bash-5.3.3" ]
--   }
-- }', '198.51.100.0');

CREATE OR REPLACE FUNCTION HostAddPackages(a_json json, a_client_ip cidr) RETURNS INT AS $$
DECLARE
  l_incoming_packages_id integer;
  l_host_id              integer;
  l_repos                json;
  l_package_repos        json;
  l_repo_url             text;
  l_package              text;
  l_repo_id              integer;
  l_package_name         text;
  l_package_version      text;
  l_package_id           integer;
  l_package_version_id   integer;

BEGIN
-- save the data, just because we can
  INSERT INTO incoming_packages (data, client_ip)
    VALUES (a_json, a_client_ip)
    RETURNING id INTO l_incoming_packages_id;

-- the enabled repositories, keyed by name: "repos" from 0.3.0 clients,
-- "repo" from 0.3.0beta clients, nothing from 0.2.x clients.
-- Disabled ones (only 0.3.0beta sends those) are skipped below.

  IF json_typeof(a_json->'repos') = 'object' THEN
    l_repos := a_json->'repos';
  ELSIF json_typeof(a_json->'repo') = 'object' THEN
    l_repos := a_json->'repo';
  END IF;

  IF json_typeof(a_json->'package_repos') = 'object' THEN
    l_package_repos := a_json->'package_repos';
  END IF;

-- host.repo keeps holding one URL, as it always has: the one the client
-- sent, or for a 0.3.0beta client the first enabled repository by name.

  IF json_typeof(a_json->'repo') = 'string' THEN
    l_repo_url := a_json->>'repo';
  ELSE
    SELECT J.value->>'url'
      INTO l_repo_url
      FROM json_each(l_repos) J
     WHERE coalesce((J.value->>'enabled')::boolean, true)
     ORDER BY J.key
     LIMIT 1;
  END IF;

-- save the host, get the id

  INSERT INTO host (name, os, version, repo)
    VALUES (a_json->>'name', a_json->>'os', a_json->>'version', coalesce(l_repo_url, ''))
    ON CONFLICT(name)
    DO UPDATE SET os      = EXCLUDED.os,
                  version = EXCLUDED.version,
                  repo    = EXCLUDED.repo
    RETURNING id INTO l_host_id;

-- replace this host's repositories

  DELETE FROM host_repo
    WHERE host_id = l_host_id;

  IF l_repos IS NOT NULL THEN
    INSERT INTO repo (url)
      SELECT DISTINCT J.value->>'url'
        FROM json_each(l_repos) J
       WHERE J.value->>'url' IS NOT NULL
         AND coalesce((J.value->>'enabled')::boolean, true)
      ON CONFLICT (url) DO NOTHING;

    INSERT INTO host_repo (host_id, repo_id, name, priority)
      SELECT l_host_id, R.id, J.key, coalesce((J.value->>'priority')::int, 0)
        FROM json_each(l_repos) J JOIN repo R ON R.url = J.value->>'url'
       WHERE coalesce((J.value->>'enabled')::boolean, true)
      ON CONFLICT ON CONSTRAINT host_repo_host_id_repo_id_key DO NOTHING;

  ELSIF l_repo_url <> '' THEN
-- a 0.2.x client: one URL and no name
    INSERT INTO repo (url)
      VALUES (l_repo_url)
      ON CONFLICT (url) DO NOTHING;

    INSERT INTO host_repo (host_id, repo_id)
      SELECT l_host_id, R.id FROM repo R WHERE R.url = l_repo_url
      ON CONFLICT ON CONSTRAINT host_repo_host_id_repo_id_key DO NOTHING;
  END IF;

-- replace this host's packages

  DELETE FROM host_package
    WHERE host_id = l_host_id;

-- each package, with the repository it came from when the client says.
-- A package from a repository this host no longer has enabled, or from
-- "unknown-repository" (pkg add of a file), gets a NULL repo_id.

  FOR l_package, l_repo_id IN
    SELECT P.package, HR.repo_id
      FROM json_array_elements_text(a_json->'packages') AS P(package)
      LEFT JOIN (SELECT J.key AS repo_name, E.package
                   FROM json_each(l_package_repos) J
                        CROSS JOIN LATERAL json_array_elements_text(
                          CASE WHEN json_typeof(J.value) = 'array' THEN J.value END
                        ) AS E(package)) PR
             ON PR.package = P.package
      LEFT JOIN host_repo HR
             ON HR.host_id = l_host_id
            AND HR.name    = PR.repo_name
  LOOP
--  split package into name and version:
--  for example: sudo-1.8.28p1
--     split on the rightmost hypen.
--     Everything to the left is package name.
--     Everything to the right is version.

    l_package_name    := substring(l_package, '(.+)-[^-]+$');
    l_package_version := substring(l_package, '.+-([^-]+)$');

    INSERT INTO package (name)
      VALUES (l_package_name)
      ON CONFLICT(name)
      DO UPDATE SET name = EXCLUDED.name
      RETURNING id INTO l_package_id;

    INSERT INTO package_version (package_id, version)
      VALUES (l_package_id, l_package_version)
      ON CONFLICT ON CONSTRAINT package_version_package_id_version_key
      DO UPDATE SET version = EXCLUDED.version
      RETURNING id INTO l_package_version_id;

    INSERT INTO host_package (host_id, package_version_id, repo_id)
      VALUES (l_host_id, l_package_version_id, l_repo_id)
      ON CONFLICT ON CONSTRAINT host_package_host_id_package_version_id_key
      DO NOTHING;

  END LOOP;

  RETURN l_incoming_packages_id;
END
$$ LANGUAGE plpgsql;
