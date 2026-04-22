File Map
========

There are a lot of files here. Some of them are well-named. Others are not.

Core files
----------

**stillebot.pike** is the main entrypoint. All invocations start here (with a
few unusual exceptions, not usually relevant, and never supported for long).
This file is the only one that cannot be live-updated, and its job is to
manage bootstrapping of other files (including triggering rebootstrapping
via signal or console). (TODO: Move the Hilfe stuff into utils?)

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

**poll.pike** provides core Twitch API call management. (Not to be confused
with modules/twitch_apis.pike which is somewhat misnamed now.) The main entry
point is twitch_api_request() which handles basically everything. There are
some additional helpers including getting user info (and translating between
user IDs and logins), get_helix_paginated which wraps all the pagination logic
(note that "Helix" is now the only Twitch API, but formerly there was Kraken),
and as of 20260423, it polls every 60 seconds to see what streams are online.
This last one is where the file name came from but is likely to soon be gone.

**connection.pike** handles channels/streams. It handles IRC and EventSub
connections, and has all core functionality relating to managing a channel:
receiving chat, sending chat, managing the EventSub conduit and distributing
events to the correct channels, etc. It is also the place where HTTP (and
WebSocket) connections are handled, although all of the *interesting* stuff
happens elsewhere.

**window.pike** provides a GUI. A lot of the code in there is very very old
and ugly, but it works. The GUI is optional and will largely be skipped if
the `--headless` parameter is given; however this file will continue to
provide stubs so that other modules can seek to create menu items.


Modules
-------

There are three directories that are searched for modules. They will be
bootstrapped in alphabetical order, but ideally, modules in a directory
should not depend on modules in the same directory, but only on something
at a higher precedence.

The **modules** directory provides base functionality. The **modules/http**
directory is all files that provide HTTP endpoints, but many of them also
provide other functionality (eg builtins). The **zz_local** directory is
untracked and can be used for local files; this idea was more relevant when
self-hosting the bot was more supported, but I try to put "personal" code
in there to avoid cluttering up the core.

Once a module is loaded, its functionality is defined entirely by itself,
not the directory it's in. The only inherent meaning to the directories is
the order of loading.


Ancillary files
---------------

**dbstatus.pike** reformats database information for the `./dbctl status`
command and is simply a helper for that.

**install.pike** creates a systemd service file. TODO: Move this into utils,
and support other types of installation, maybe autodetecting.

**utils.pike** handles `pike stillebot --exec=X` invocations. For any value
of X, it will run X() inside utils. Used for all manner of CLI tools.
