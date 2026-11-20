-- Read access for the SamDrucker reporting website.
--
-- The website connects as a login in the reporting role. Until now,
-- reporting could read only host, repo and host_repo, which is enough to
-- list hosts but not their packages. This grants SELECT on the package
-- tables too. Nothing else changes: reporting still cannot write anything,
-- and the check-in endpoint (postie, in the delivery role) is not affected.
--
-- Run as the owner of the tables. Safe to run more than once.

GRANT SELECT ON host_package, package, package_version TO reporting;

-- A login for the website. Set a real password, put it in
-- /usr/local/etc/samdrucker/samdruckerweb.conf, and allow this user from
-- the web server in pg_hba.conf. Skip this if you already have one.
--
-- CREATE USER viewer WITH LOGIN PASSWORD '[change me]' IN ROLE reporting;
