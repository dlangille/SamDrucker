-- Bring samdrucker and samdrucker.dev to the same schema.
--
-- Compared with pg_dump -s on 2026-11-19, samdrucker.dev was ahead of
-- samdrucker in everything except one leftover function. This script
-- moves both databases to the samdrucker.dev layout, minus that function.
--
-- It is safe to run on either database, and to run more than once:
-- every step checks first and does nothing if the change is already there.
-- Run it as postgres (the owner of all objects), on samdrucker.dev first.
--
-- Nothing changes for clients or for anyone running the query functions.
-- The repo and host_repo tables, which exist only on samdrucker.dev and
-- are not used by any function yet, are deliberately left alone here.
-- They belong to the multi-repository change (issue #1), whose own update
-- script will create or alter them on both databases.

BEGIN;

-- 1. HostAddPackages(json) is the pre-0.2 version, from before the client
--    IP was recorded. samdrucker.php calls only HostAddPackages(json, cidr),
--    so the one-argument form is dead code. It is still on samdrucker.

DROP FUNCTION IF EXISTS public.hostaddpackages(json);

-- 2. host_package.package_version_id has no foreign key on samdrucker.
--    Without it, deleting a package_version leaves host_package rows that
--    point at nothing, and the query functions silently skip them.
--    Add it NOT VALID: new and changed rows are checked from now on, and
--    existing rows are checked later by VALIDATE (see the end of this file).
--    Databases created from database-postgresql.sql already have this key,
--    under the name host_package_package_version_id_fkey, so look for any
--    foreign key from host_package to package_version, whatever its name.

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

-- 3. The index which supports that foreign key. Without it, every delete
--    from package_version scans all of host_package.

CREATE INDEX IF NOT EXISTS fki_host_package_package_version_id_fk
  ON public.host_package USING btree (package_version_id);

-- 4. On samdrucker.dev, host_package_host_id_fkey also has ON UPDATE CASCADE.
--    host.id never changes in practice, so this only makes the two match.
--    confupdtype 'c' means ON UPDATE CASCADE.

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

COMMIT;

-- 5. Optional, run by hand on each database. First count the existing
--    host_package rows which point at a missing package_version:
--
--   SELECT count(*)
--     FROM host_package HP
--    WHERE NOT EXISTS (SELECT 1 FROM package_version PV
--                       WHERE PV.id = HP.package_version_id);
--
--    If that is 0, and the key was added by this script (it is NOT VALID
--    only then), mark it as checked for all rows:
--
--   ALTER TABLE public.host_package
--     VALIDATE CONSTRAINT host_package_package_version_id_fk;
--
--    If it is not 0, those rows are already invisible to every query
--    function; delete them, then VALIDATE.
