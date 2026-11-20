-- SamDrucker 0.3.0: the database changes for this release.
--
-- Run this once on an existing SamDrucker database, then run
-- procedures.sql (which replaces HostAddPackages). Run both as the owner
-- of the tables, after taking a backup:
--
--   psql samdrucker -f updates-2026.11.19.sql
--   psql samdrucker -f procedures.sql
--
-- If the database is from a release before 0.2.4, run
-- updates-2020.08.28.sql before this script.
--
-- It is safe to run more than once: every step checks first and does
-- nothing if the change is already there. Everything happens in one
-- transaction, so if any step fails, nothing is changed.
--
-- Nothing is removed that a client or a query function uses. host.repo is
-- still filled in on every check-in, and every existing query function
-- returns what it did before.
--
-- Part A tidies up differences between installs, so every database starts
-- from the same schema. Part B adds what 0.3.0 needs to record every
-- repository a host uses (issue #1).

\set ON_ERROR_STOP on

BEGIN;

-- ======================================================================
-- Part A: one schema for every install
--
-- Compared with pg_dump -s on 2026-11-19, the samdrucker and
-- samdrucker.dev databases had drifted apart, and both differ a little
-- from an install made from database-postgresql.sql.
-- ======================================================================

-- A1. HostAddPackages(json) is the pre-0.2 version, from before the client
--     IP was recorded. samdrucker.php calls only HostAddPackages(json, cidr),
--     so the one-argument form is dead code. Some old databases still have it.

DROP FUNCTION IF EXISTS public.hostaddpackages(json);

-- A2. Some databases have no foreign key on host_package.package_version_id.
--     Without it, deleting a package_version leaves host_package rows that
--     point at nothing, and the query functions silently skip them.
--     Add it NOT VALID: new and changed rows are checked from now on, and
--     existing rows can be checked later by VALIDATE (see the end of this
--     file). Databases created from database-postgresql.sql already have
--     this key, under the name host_package_package_version_id_fkey, so look
--     for any foreign key from host_package to package_version, whatever
--     its name.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE contype   = 'f'
                    AND conrelid  = 'public.host_package'::regclass
                    AND confrelid = 'public.package_version'::regclass) THEN
    ALTER TABLE public.host_package
      ADD CONSTRAINT host_package_package_version_id_fk
      FOREIGN KEY (package_version_id) REFERENCES public.package_version(id)
      ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;
  END IF;
END
$$;

-- A3. The index which supports that foreign key. Without it, every delete
--     from package_version scans all of host_package.

CREATE INDEX IF NOT EXISTS fki_host_package_package_version_id_fk
  ON public.host_package USING btree (package_version_id);

-- A4. Give host_package_host_id_fkey ON UPDATE CASCADE, as some databases
--     already have. host.id never changes in practice, so this only makes
--     every install the same. confupdtype 'c' means ON UPDATE CASCADE.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname     = 'host_package_host_id_fkey'
                AND conrelid    = 'public.host_package'::regclass
                AND confupdtype <> 'c') THEN
    ALTER TABLE public.host_package
      DROP CONSTRAINT host_package_host_id_fkey;
    ALTER TABLE public.host_package
      ADD CONSTRAINT host_package_host_id_fkey
      FOREIGN KEY (host_id) REFERENCES public.host(id)
      ON UPDATE CASCADE ON DELETE CASCADE;
  END IF;
END
$$;

-- ======================================================================
-- Part B: record every repository a host uses
--
-- Before 0.3.0, each host had one repository: the URL in host.repo.
-- With pkgbase, a host uses several at once, for example FreeBSD-base for
-- the base system and FreeBSD-ports or a local poudriere repository for
-- everything else. This adds:
--
--   repo                 one row per repository URL seen from any host
--   host_repo            which repositories each host has enabled, with the
--                        name and priority that host gives each one
--   host_package.repo_id which repository each installed package came from
--
-- A repository is identified by its URL, not its name: the same name
-- (FreeBSD-base, local) points at different URLs on different hosts.
--
-- Some databases already have repo and host_repo, created by hand during
-- development (repo.name instead of repo.url, host_repo without name and
-- priority). Those are brought to the same layout. If repo already holds
-- a row which does not look like a URL, the script stops, and nothing is
-- changed.
-- ======================================================================

-- B1. repo

CREATE TABLE IF NOT EXISTS public.repo (
  id         int PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
  url        text NOT NULL,
  date_added timestamp without time zone NOT NULL DEFAULT timezone('UTC'::text, now()),
  enabled    boolean NOT NULL DEFAULT true,
  CONSTRAINT repo_url_key UNIQUE (url)
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'repo'
                AND column_name  = 'name') THEN

    IF EXISTS (SELECT 1 FROM public.repo WHERE name !~ '://') THEN
      RAISE EXCEPTION 'repo.name holds values which are not URLs; '
                      'fix or delete those rows, then run this again';
    END IF;

    ALTER TABLE public.repo RENAME COLUMN name TO url;
    ALTER TABLE public.repo RENAME CONSTRAINT unique_name_repo TO repo_url_key;
  END IF;
END
$$;

COMMENT ON TABLE  public.repo IS
  'one row per pkg repository URL reported by any host';
COMMENT ON COLUMN public.repo.url IS
  'the repository URL, as in pkg.conf; this, not the name, identifies a repository';
COMMENT ON COLUMN public.repo.enabled IS
  'repos are enabled by default
when no longer in service, set to false';

-- B2. host_repo

CREATE TABLE IF NOT EXISTS public.host_repo (
  host_id  int NOT NULL REFERENCES public.host(id) ON UPDATE CASCADE ON DELETE CASCADE,
  repo_id  int NOT NULL REFERENCES public.repo(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT host_repo_host_id_repo_id_key UNIQUE (host_id, repo_id)
);

ALTER TABLE public.host_repo ADD COLUMN IF NOT EXISTS name     text;
ALTER TABLE public.host_repo ADD COLUMN IF NOT EXISTS priority int NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS host_repo_repo_id_idx ON public.host_repo (repo_id);

COMMENT ON TABLE  public.host_repo IS
  'the enabled repositories of each host, replaced on every check-in';
COMMENT ON COLUMN public.host_repo.name IS
  'the name this host gives the repository (FreeBSD-base, local, ...);
NULL when the host runs a 0.2.x client, which sends only a URL';
COMMENT ON COLUMN public.host_repo.priority IS
  'the pkg priority this host gives the repository';

-- B3. host_package.repo_id

ALTER TABLE public.host_package
  ADD COLUMN IF NOT EXISTS repo_id int
  REFERENCES public.repo(id) ON UPDATE CASCADE ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS host_package_repo_id_idx ON public.host_package (repo_id);

COMMENT ON COLUMN public.host_package.repo_id IS
  'the repository this package was installed from; NULL when the host
runs a 0.2.x client, when the package was not installed from a
repository (pkg add of a file), or when that repository is no longer
enabled on the host';

-- B4. permissions, for the roles created by
--     database-postgresql-permissions.sql. Each role is granted only if
--     it exists.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'delivery') THEN
    GRANT SELECT, INSERT                 ON public.repo      TO delivery;
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.host_repo TO delivery;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reporting') THEN
    GRANT SELECT ON public.repo, public.host_repo TO reporting;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rsyncer') THEN
    GRANT SELECT ON public.repo, public.host_repo TO rsyncer;
    GRANT SELECT ON SEQUENCE public.repo_id_seq   TO rsyncer;
  END IF;
END
$$;

COMMIT;

-- Optional, run by hand afterwards. If step A2 added the foreign key, it
-- is NOT VALID: rows already in host_package were not checked. To check
-- them, first count the rows which point at a missing package_version:
--
--   SELECT count(*)
--     FROM host_package HP
--    WHERE NOT EXISTS (SELECT 1 FROM package_version PV
--                       WHERE PV.id = HP.package_version_id);
--
-- If that is 0, mark the key as checked for all rows:
--
--   ALTER TABLE public.host_package
--     VALIDATE CONSTRAINT host_package_package_version_id_fk;
--
-- If it is not 0, those rows are already invisible to every query
-- function; delete them, then VALIDATE.
