PostgreSQL configuration
========================

In order to provide reliable, secure, dependable configuration storage,
PostgreSQL is used with the following configuration options:

* Locally, peer authentication.
* To allow replication, both servers must set listen_addresses = '*' and
  ssl = on
* Copy the necessary certificates into the Postgres data directory and
  chown/chmod them as needed
* Need to know which SSL root cert ultimately signs the required certs.
  Currently this is /etc/ssl/certs/ISRG_Root_X1.pem but may need to change.
* Connect: PGSSLROOTCERT=/etc/ssl/certs/ISRG_Root_X1.pem PGSSLCERT=certificate.pem PGSSLKEY=privkey.pem psql -h sikorsky.rosuav.com
* Create a publication on Sikorsky:
  stillebot=# create publication multihome for tables in schema stillebot;
* Create a subscription on Gideon:
  stillebot=# create subscription multihome connection 'dbname=stillebot host=sikorsky.rosuav.com user=rosuav sslmode=require sslcert=/home/rosuav/stillebot/certificate.pem sslkey=/home/rosuav/stillebot/pk_psql.pem sslrootcert=/etc/ssl/certs/ISRG_Root_X1.pem application_name=multihome' publication multihome;
  - Initial copy SHOULD be done automatically but it doesn't seem to be.
  - Replication nonfunctional.

cp /etc/letsencrypt/live/sikorsky.rosuav.com/fullchain.pem /etc/postgresql/15/main/certificate.pem
cp /etc/letsencrypt/live/sikorsky.rosuav.com/privkey.pem /etc/postgresql/15/main/
chown postgres: *.pem
chmod 600 *.pem
-- TODO: Do this on both Gideon and Sikorsky, as part of their renewal-hooks


To make things work, *tables* must exist on both ends; the replication
will only transfer row changes. There will need to be a bot-managed
table update system.

The code in pgssl.pike works as long as Pike has the necessary patches to allow
SSL.Context() configuration for an Sql.Sql() connection. It will then be able to
run the bot on either Gideon or Sikorsky and talk to a database on either Gideon
or Sikorsky. (TODO: Open up Gideon with the same SSL certificate authentication.)
Ultimately, migrate all configs into the database, and then have a way to select
which DB host is in use.

NOTE: Attempting to connect to gideon.rosuav.com from Sikorsky MAY result in an
unsuccessful attempt to use IPv6. (Sigh. Why can't it be successful?) Instead,
use the name ipv4.rosuav.com to force protocol.
