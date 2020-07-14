To deploy a SamDrucker PostgreSQL database:

- create the PostgreSQL database
- update pg_hba.conf on the PostgreSQL server to allow connections from your webserver
- create the tables via `database-postgresql.sql`
- add the stored procedures with `procedures.sql`
- invoke `database-postgresql-permissions.sql` to configure database permissions

`check_samdrucker_host_checkins` is a Nagios plugin for verifying that all
known hosts have checked in during the past 25 hours.
