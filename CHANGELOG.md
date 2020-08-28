# Changelog

## host table

Any changes to the `host` table with automatically update the `date_updated`
field. See `update_date_updated` in `PostgreSQL/database-postgresql.sql`.

## 2.4

With this release, you can set a host to be not enabled. Perhaps you have a
host which is no longer in use but you want to keep the data.

When upgrading to this release, be sure to run these scripts:

* `PostgreSQL/updates-2020.08.28.sql`
* `PostgreSQL/procedures.sql`

```
update host set enabled = false where name in ('foo', 'bar');
```

New versions of the query functions have been created. These take a boolean
parameter as their last arguement. This allows you to query hosts which are
no longer enabled (false). The existing functions will now only query
enabled hosts. You can retain existing behaviour by leaving all hosts
enabled.
