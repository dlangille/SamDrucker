# What is Sam Drucker?

SamDrucker is a collection of small components which create a centralized
list of all packages on all hosts.

Each component is designed to be:

* small
* simple
* easily written
* flexiable
* few, if any, dependencies

## The components

* client - collects the list of packages and posts it to the server
* server - accepts the list of packages and adds it to the database
* database - tables and stored procedures for the catalog of packages

Each component can be written in whatever languages you want. Collect
the packages in any manner you want. This can be done remotely on the host
or centrally on a management tool, such as Ansible.

Pick whatever languages you want.

## Other ideas

It was mentioned elsewhere that Ansible or Spacewalk can help here. I want
something completely independent. These tools are great at collecting information.

I didn't want to use a large number of dependencies or huge packages.

## Current status

A sample client and web service have been created as proof of concept.
They are deployed in my home network, active on about 90 hosts.

A database schema has been created for PostgreSQL, my database of personal
choice, but this should work on any other database. Patches welcome here.

## Next major step

At present, queries of the database are possible only via command line tools.

I'd like to create a simple web interface.

Anyone is weclome to help write this stuff.


## Wiki

You can read more in [the wiki](https://github.com/dlangille/SamDrucker/wiki).
