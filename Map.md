File Map
========

There are a lot of files here. Some of them are well-named. Others are not.

Core files
----------

**stillebot.pike** is the main entrypoint. All invocations start here (with a
few unusual exceptions, not usually relevant, and never supported for long).
This file is the only one that cannot be live-updated, and its job is to
manage bootstrapping of other files. (TODO: Remove the console and Hilfe code
from there, maybe put the Hilfe stuff into utils?)

**globals.pike** autoexports all non-private symbols, so anything in that file
can be accessed anywhere. It provides all the core inheritables, myriad minor
leaf functions, and anything that isn't considered big enough to have its own
file. Which includes some pretty big things like the Markdown parser, which
could potentially be migrated out.

**pgssl.pike** is a low level library that talks the PostgreSQL wire protocol
over an SSL encrypted socket. Originally the plan was to use this to learn,
and then switch back to Sql.Sql() with what I understood, but that switching
back is probably never going to happen now. At least in theory, this should
work for any Postgres database over SSL, with no Stillebot-specific code.
NOTE: Fully asynchronous I/O. Everything is non-blocking and promise-based.

**database.pike** has all of the Stillebot-specific database code. Some of the
helper functions are fairly trivial and could be replaced with queries in the
places they're used; but the vast majority of queries use more helpful helpers
such as config querying and mutation. Includes the table structure; note that
some parts of it have never been tested in their current form. Some day I need
to spin up a brand new database and launch a replicant bot on it, just to make
sure everything works, because it probably won't. NOTE: Database *backups* are
not handled here; there is a completely external nightly backup using pg_dump.

"poll.pike", "connection.pike", "window.pike"

Modules
-------

"modules", "modules/http", "zz_local"

Ancillary files
---------------

**dbstatus.pike** reformats database information for the `./dbctl status`
command and is simply a helper for that.

**install.pike** creates a systemd service file. TODO: Move this into utils,
and support other types of installation, maybe autodetecting.

**sslport.pike** is a debug file, not sure if I need it, maybe it should go
into shed instead.

**timings.pike** was for some performance testing I did at some point.

**utils.pike** handles `pike stillebot --exec=X` invocations. For any value
of X, it will run X() inside utils. Used for all manner of CLI tools.
