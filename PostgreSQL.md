PostgreSQL configuration
========================

In order to provide reliable, secure, dependable configuration storage,
PostgreSQL is used with the following configuration options:

* Locally, peer authentication.
* To allow replication, both servers must set:
  listen_addresses = '*'
  ssl = on
  wal_level = logical
* Copy the necessary certificates into the Postgres data directory and
  chown/chmod them as needed
* Need to know which SSL root cert ultimately signs the required certs.
  Currently this is /etc/ssl/certs/ISRG_Root_X1.pem but may need to change.
* Connect: PGSSLROOTCERT=/etc/ssl/certs/ISRG_Root_X1.pem PGSSLCERT=certificate.pem PGSSLKEY=privkey.pem psql -h sikorsky.rosuav.com
* Create a publication on Sikorsky:
  stillebot=# create publication multihome for all tables;
* Create a subscription on Gideon:
  stillebot=# create subscription multihome connection 'dbname=stillebot host=sikorsky.rosuav.com user=rosuav sslmode=require sslcert=/etc/postgresql/16/main/certificate.pem sslkey=/etc/postgresql/16/main/privkey.pem sslrootcert=/etc/ssl/certs/ISRG_Root_X1.pem application_name=multihome' publication multihome with (origin = none);
  - Note that the user 'rosuav' must have the Replication attribute (confirm with `\du+`).
* Create the corresponding publication on Gideon, and subscription on Sikorsky:
  stillebot=# create subscription multihome connection 'dbname=stillebot host=ipv4.rosuav.com user=rosuav sslmode=require sslcert=/etc/postgresql/16/main/certificate.pem sslkey=/etc/postgresql/16/main/privkey.pem sslrootcert=/etc/ssl/certs/ISRG_Root_X1.pem application_name=multihome' publication multihome with (origin = none, copy_data = false);
  - Note: Do not copy_data both directions.

cp /etc/letsencrypt/live/sikorsky.rosuav.com/fullchain.pem /etc/postgresql/16/main/certificate.pem
cp /etc/letsencrypt/live/sikorsky.rosuav.com/privkey.pem /etc/postgresql/16/main/
chown postgres: *.pem
chmod 600 *.pem
-- This is done on both Gideon and Sikorsky, as part of their renewal-hooks


To make things work, tables must exist on both ends. New tables must be created
by the bot on both ends, and then properly populated. TODO: Automatically run
a refreshrepl after a table creation or alteration.

The code in pgssl.pike works as long as Pike has the necessary patches to allow
SSL.Context() configuration for an Sql.Sql() connection. It will then be able to
run the bot on either Gideon or Sikorsky and talk to a database on either Gideon
or Sikorsky. Ultimately, migrate all configs into the database, and then the
active DB host will be whichever one (or ones!) does not have read-only mode set.

NOTE: Attempting to connect to gideon.rosuav.com from Sikorsky MAY result in an
unsuccessful attempt to use IPv6. (Sigh. Why can't it be successful?) Instead,
use the name ipv4.rosuav.com to force protocol.

Bot/Database transfer procedure
-------------------------------

Initially, both databases are read-write. Replication will be occurring both
directions, and all should be stable. Assume that Sikorsky needs to be brought
down.

1. update stillebot.settings set active_bot = 'ipv4.rosuav.com';
2. On Sikorsky, `./dbctl down`
3. Sikorsky: `./dbctl stat` until no rows with application_name 'stillebot'
   remain (they've all switched to 'stillebot-ro').
4. At this point, all clients will be talking to Gideon's database, and all
   websockets will be talking to Gideon.
5. It is now safe to bring down Sikorsky's DB and bot. There may be some
   outage of web requests until clients start using the other IP.
   TODO: Test this - make sure clients will test both. Far from guaranteed.
6. To bring Sikorsky up again: `./dbctl up`
7. update stillebot.settings set active_bot = 'sikorsky.rosuav.com';

At this point, everything should be back to normal.

NOTE: Marking a database as "down" is necessary to prevent split-brain syndrome.
Once replication breaks, there should be only ONE active database until the
replication resumes; otherwise, it's possible that conflicts will occur between
the two databases. TODO: Test that the DB is still "down" after a reboot if it
was "down" prior to it.

Bidirectional replication
-------------------------

The above notes are written on the assumption that PostgreSQL v16 or greater is
in use. This introduces (above what is available in Postgres 15) the 'origin'
replication parameter, which allows true master-master bidirectional replication
without looping transactions back.

This requires a PG not available in the Debian Bookworm repos, so the bookworm-pgdg
repo is used instead. Once PG 16 is available from Debian (should be in Trixie),
remove this repo and use the Debian one instead.

Changes to table structure
--------------------------

DDL statements are not replicated. Thus all changes to table structure (including
and especially the creation of new tables) must be done on both databases at once.
Start with both databases down and replicating. (Use `./dbctl dn` on whichever
database(s) were up.) During this time, all actual changes will be queued in the
bot itself, with no actual DB updates being done.

With the databases quiescent, running the bot with `--dbupdate` will update all
databases with the necessary changes. Then when it's done, use `./dbctl refreshrepl`
on both ends if any new tables have been created, otherwise go ahead and bring the
database back up again.

If any database is in read-write mode, attempting an update will silently succeed
as long as nothing needs to be changed, but otherwise will error out.

TODO: Test all this in a PG16 world.
