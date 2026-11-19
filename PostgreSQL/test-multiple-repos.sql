-- Tests for HostAddPackages() with 0.2.x, 0.3.0beta and 0.3.0 check-ins.
--
-- Run this on a scratch database which already has the 0.3.0 schema and
-- procedures, either upgraded or freshly created. From this directory:
--
--   upgraded:  createdb samdrucker_test
--              pg_dump samdrucker.dev | psql -q samdrucker_test
--              psql samdrucker_test -f updates-2026.11.19-reconcile.sql
--              psql samdrucker_test -f updates-2026.11.19-multiple-repos.sql
--              psql samdrucker_test -f procedures.sql
--              psql samdrucker_test -f test-multiple-repos.sql
--
--   fresh:     createdb samdrucker_fresh
--              psql samdrucker_fresh -f database-postgresql.sql
--              psql samdrucker_fresh -f procedures.sql
--              psql samdrucker_fresh -f test-multiple-repos.sql
--
-- Every check raises an exception when it fails, and the script stops at
-- the first one. It ends with "all tests passed". Everything it does is
-- rolled back, so the database is left as it was. The hosts it uses are
-- named *.test.invalid, which no real host can have.

\set ON_ERROR_STOP on

BEGIN;

-- 1. a 0.2.x client: repo is one URL, no repos, no package_repos

SELECT HostAddPackages('{
  "name": "old.test.invalid",
  "os": "FreeBSD",
  "version": "14.3-RELEASE-p5",
  "repo": "pkg+https://pkg.test.invalid/FreeBSD:14:amd64/quarterly",
  "packages": [ "bash-5.3.3", "sudo-1.9.17p2" ]
}', '198.51.100.1');

DO $$
BEGIN
  IF (SELECT repo FROM host WHERE name = 'old.test.invalid')
     <> 'pkg+https://pkg.test.invalid/FreeBSD:14:amd64/quarterly' THEN
    RAISE EXCEPTION '1: host.repo is wrong for a 0.2.x client';
  END IF;
  IF (SELECT count(*) FROM ReposOnHost('old.test.invalid') WHERE name IS NULL
         AND url = 'pkg+https://pkg.test.invalid/FreeBSD:14:amd64/quarterly') <> 1
  OR (SELECT count(*) FROM ReposOnHost('old.test.invalid')) <> 1 THEN
    RAISE EXCEPTION '1: expected one unnamed repository for a 0.2.x client';
  END IF;
  IF (SELECT count(*) FROM PackagesOnHostShowRepo('old.test.invalid') WHERE url IS NULL) <> 2 THEN
    RAISE EXCEPTION '1: packages from a 0.2.x client should have no repository';
  END IF;
  IF (SELECT count(*) FROM PackagesOnHost('old.test.invalid')) <> 2 THEN
    RAISE EXCEPTION '1: PackagesOnHost() should return 2 packages';
  END IF;
END
$$;

-- 2. a 0.3.0beta client: repo is `pkg repositories`, disabled ones included

SELECT HostAddPackages('{
  "name": "beta.test.invalid",
  "os": "FreeBSD",
  "version": "15.1-RELEASE-p7",
  "repo": {
    "FreeBSD-ports": { "url": "pkg+https://pkg.test.invalid/FreeBSD:15:amd64/quarterly",
                       "enabled": false, "priority": 0 },
    "FreeBSD-base":  { "url": "http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
                       "enabled": true,  "priority": 0 },
    "local":         { "url": "http://proxy.test.invalid/fedex/FreeBSD:15:amd64",
                       "enabled": true,  "priority": 5 }
  },
  "packages": [ "FreeBSD-acct-15.1p4", "bash-5.3.3" ]
}', '198.51.100.2');

DO $$
BEGIN
  IF (SELECT repo FROM host WHERE name = 'beta.test.invalid')
     <> 'http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1' THEN
    RAISE EXCEPTION '2: host.repo should be the first enabled repository by name';
  END IF;
  IF (SELECT string_agg(name || '=' || priority, ',' ORDER BY name)
        FROM ReposOnHost('beta.test.invalid')) <> 'FreeBSD-base=0,local=5' THEN
    RAISE EXCEPTION '2: expected FreeBSD-base and local only, with their priorities';
  END IF;
  IF (SELECT count(*) FROM PackagesOnHostShowRepo('beta.test.invalid') WHERE url IS NULL) <> 2 THEN
    RAISE EXCEPTION '2: a 0.3.0beta client does not say where packages came from';
  END IF;
END
$$;

-- 3. a 0.3.0 client, as samdrucker.sh 0.3.0 sends it

SELECT HostAddPackages('{
  "name": "new.test.invalid",
  "os": "FreeBSD",
  "version": "15.1-RELEASE-p7",
  "repo": "http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
  "repos": {
    "FreeBSD-base": { "url": "http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
                      "enabled": true, "priority": 0 },
    "local":        { "url": "http://proxy.test.invalid/fedex/FreeBSD:15:amd64",
                      "enabled": true, "priority": 0 }
  },
  "packages": [ "FreeBSD-acct-15.1p4", "bash-5.3.3", "my-tool-1.0" ],
  "package_repos": {
    "FreeBSD-base":       [ "FreeBSD-acct-15.1p4" ],
    "local":              [ "bash-5.3.3" ],
    "unknown-repository": [ "my-tool-1.0" ]
  }
}', '198.51.100.3');

DO $$
BEGIN
  IF (SELECT string_agg(package_version || '=' || coalesce(repo_name, '-'), ',' ORDER BY package_version)
        FROM PackagesOnHostShowRepo('new.test.invalid'))
     <> 'FreeBSD-acct-15.1p4=FreeBSD-base,bash-5.3.3=local,my-tool-1.0=-' THEN
    RAISE EXCEPTION '3: packages are not linked to the right repositories: %',
      (SELECT string_agg(package_version || '=' || coalesce(repo_name, '-'), ',' ORDER BY package_version)
         FROM PackagesOnHostShowRepo('new.test.invalid'));
  END IF;
-- hosts 2 and 3 share two URLs: each URL must be stored once
  IF (SELECT count(*) FROM repo WHERE url LIKE 'http://proxy.test.invalid/%') <> 2 THEN
    RAISE EXCEPTION '3: a repository URL was stored more than once';
  END IF;
END
$$;

-- 4. the same name for a different URL on another host

SELECT HostAddPackages('{
  "name": "other-site.test.invalid",
  "os": "FreeBSD",
  "version": "15.1-RELEASE-p7",
  "repo": "http://other-proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
  "repos": {
    "FreeBSD-base": { "url": "http://other-proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
                      "enabled": true, "priority": 0 }
  },
  "packages": [ "FreeBSD-acct-15.1p4" ],
  "package_repos": { "FreeBSD-base": [ "FreeBSD-acct-15.1p4" ] }
}', '198.51.100.4');

DO $$
BEGIN
  IF (SELECT url FROM PackagesOnHostShowRepo('other-site.test.invalid'))
     <> 'http://other-proxy.test.invalid/FreeBSD:15:amd64/base_release_1' THEN
    RAISE EXCEPTION '4: FreeBSD-base on this host must be its own URL';
  END IF;
END
$$;

-- 5. the next check-in replaces everything for that host:
--    bash removed, php85 added, local now disabled

SELECT HostAddPackages('{
  "name": "new.test.invalid",
  "os": "FreeBSD",
  "version": "15.1-RELEASE-p8",
  "repo": "http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
  "repos": {
    "FreeBSD-base": { "url": "http://proxy.test.invalid/FreeBSD:15:amd64/base_release_1",
                      "enabled": true, "priority": 0 }
  },
  "packages": [ "FreeBSD-acct-15.1p4", "php85-8.5.0" ],
  "package_repos": {
    "FreeBSD-base": [ "FreeBSD-acct-15.1p4" ],
    "local":        [ "php85-8.5.0" ]
  }
}', '198.51.100.3');

DO $$
BEGIN
  IF (SELECT version FROM host WHERE name = 'new.test.invalid') <> '15.1-RELEASE-p8' THEN
    RAISE EXCEPTION '5: host.version was not updated';
  END IF;
  IF (SELECT string_agg(package_version || '=' || coalesce(repo_name, '-'), ',' ORDER BY package_version)
        FROM PackagesOnHostShowRepo('new.test.invalid'))
     <> 'FreeBSD-acct-15.1p4=FreeBSD-base,php85-8.5.0=-' THEN
    RAISE EXCEPTION '5: packages were not replaced: %',
      (SELECT string_agg(package_version || '=' || coalesce(repo_name, '-'), ',' ORDER BY package_version)
         FROM PackagesOnHostShowRepo('new.test.invalid'));
  END IF;
  IF (SELECT count(*) FROM ReposOnHost('new.test.invalid')) <> 1 THEN
    RAISE EXCEPTION '5: repositories were not replaced';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM HostsWithPackage('php85') AS H(host) WHERE H.host = 'new.test.invalid') THEN
    RAISE EXCEPTION '5: HostsWithPackage() does not find php85';
  END IF;
END
$$;

\echo all tests passed

ROLLBACK;
