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

Conflicts
---------

If true multi-master replication is the goal, this would mean the potential for
transactions that succeed on their respective ends, but conflict on replication.
Likely causes of this include:

* Any table: Two transactions each create a new row, using the SERIAL, and then
  conflict on the primary key. Very annoying since there's no easy way to fix it,
  plus it's something that could easily happen with busy tables.
* stillebot.commands: Two transactions each "update set active = false where..."
  followed by "insert (channel, cmdname, active = true)". These will be separate
  command entries. Two likely possibilities:
  - Each incoming replication transaction does the full searched update. This is
    subtle, since neither of them will know that there's a problem; they'll just
    have desynchronized data (each one getting the value that was set by the one
    at the other end), since each will have set its own one to inactive.
  - The exact tuple change is what gets replicated out. The incoming transactions
    will fail, since each one will re-deactivate the same previous row (this part
    is fine), and then insert a new active row (thus causing a conflict).
  - Either way, the correct resolution is to deactivate the one with the lower
    timestamp. In the extremely unlikely event that two nodes simultaneously do a
    rollback (which involves updating an older row to be active), there's no way
    to know which one should "win", so an arbitrary decision of "the one that was
    originally newer wins" is no worse than any other.
  - Resolution: On detection of problem:
    - Connect to both databases.
    - On each database:
      update stillebot.commands set active = false where twitchid = :channel and cmdname = :cmd and active = true returning id, created;
      This should reenable replication.
    - Determine the winner - the one with the newer 'created' value.
    - On either database, update set active = true where id = winner.
    - Signal all websockets to push out changes.
    - Conflict resolution should be done always and only by the active_bot.
    - Conflict recognition can be done through the local log exclusively - any time
      there's a conflict, it will be in both logs. You know, like how Mum always
      used to say: it takes two to fight.
* stillebot.config: Several failure modes possible here.
  - The application can either upsert ("insert, on conflict update") or delete.
  - Note that delete currently is not supported, but make plans for it to be sure
    replication won't fail.
  - Dual upsert: The row didn't exist. What gets replicated? The full upsert, or
    the resultant insert? If the latter, will cause a PK conflict and replication
    failure; if the former, will result in each end overwriting with the other's.
    No easy resolution available. Probably just pick arbitrarily :(
  - Upsert-insert and delete: The row didn't exist. One end attempts to set it,
    the other attempts to delete it. The searched delete will simply do nothing
    if it doesn't find it, but will delete the newly-inserted row. OOS depending
    on transaction ordering. No easy resolution available.

TEST ME:

* Can I trigger a replication failure in psql?
  - Begin transactions on both ends
  - Make the conflicting updates. Should have no issues at this point.
  - Commit one end. What happens on the other?
  - Commit other end. What happens? Watch both logs.
* If it's not that easy:
  - Disable replication
  - Make the updates (autocommit would be fine)
  - Reenable replication, watch the logs
* Can an application see that replication has failed? This won't catch the OOS
  errors, but would at least get the ones that are blocking future replication.
  - And if it can, can it see what the transaction did, or at least where the
    conflict is? Maybe there's another change that can be done that fixes it.
