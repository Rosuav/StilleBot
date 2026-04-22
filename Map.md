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

"pgssl.pike", "database.pike", "poll.pike", "connection.pike", "window.pike"

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
