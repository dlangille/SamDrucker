This directory contains SamDrucker server in various languages.

A server needs to:

1. capture the incoming JSON data
1. connect to the database
1. invoke the `HostAddPackages()` function using the JSON
1. disconnect

You can use whatever tools you want to create a server.

The scripts and dependencies are listed below:

php - `samdrucker.php`

* `php` - tested with php 7.2 & 7.4
* `php-pgsql` - for PostgreSQL database connection
