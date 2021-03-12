WebSockets in StilleBot
=======================

If StilleBot has a web interface (if an HTTP(S) listen address is set), its
front end and back end will rely heavily on websockets for real-time sharing
of synchronized data.

Every established websocket has two identifying values: a type and a group.
The type is a keyword, with valid values being defined in the code by modules
that inherit websocket_handler; any other values are errors. The group is
either a string or an integer, and its meaning depends on the type.

Type          | Groups
--------------|-----------------------------
songrequest   | "(sole)", not in active use
hypetrain     | Twitch channel ID (integer)
subpoints     | Display nonce
chan_giveaway | Twitch channel name (string)
chan_monitors | Either "#channel" or "nonce#channel"

Simplified usage for common cases
---------------------------------

On the back end, if vars `ws_type` and `ws_group` are set, module `ws_sync.js`
will be automatically loaded, which will establish a websocket and call render
from the corresponding module - eg if `ws_type` is `"subpoints"`, the module
`subpoints.js` will be loaded, and its render() function called whenever fresh
data is available. To provide this data, define a function on the back end,
`mapping get_state(string|int group)`. Signal updates with send_updates_all,
and the rest should take care of itself.

For groups that involve a collection of items, partial updates can be sent.
The front end will initially receive a data mapping with an array of items,
where each item has an id; subsequently, it can receive a partial update with
an id and, unless the item has been deleted, a new data mapping.

    Initial: {"items": [{"id": "foo", ...}, ...]}
    Update: {"id": "foo", "data": {"id": "foo", ...}}
    Delete: {"id": "foo"} or {"id": "foo", "data": 0}

Using these sockets outside of StilleBot
----------------------------------------

These websockets constitute a weak API, in that there is some small measure of
backward compatibility maintained. In particular, the hype train socket can be
used externally, so if you want to build on top of what I've made, go ahead!
