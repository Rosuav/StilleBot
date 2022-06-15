WebSockets in StilleBot
=======================

If StilleBot has a web interface (if an HTTP(S) listen address is set), its
front end and back end will rely heavily on websockets for real-time sharing
of synchronized data.

Every established websocket has two identifying values: a type and a group.
The type is a keyword, with valid values being defined in the code by modules
that inherit websocket_handler; any other values are errors. The group is
either a string or an integer, and its meaning depends on the type.

Type           | Groups
---------------|-----------------------------
chan_commands  | Either "#channel" or "cmdname#channel"
chan_giveaway  | Either "view#channel" or "control#channel"
chan_messages  | uid#channel
chan_monitors  | Either "#channel" or "nonce#channel"
chan_mpn       | document#channel
chan_vlc       | Either "#channel" or "blocks#channel"
chan_voices    | #channel
chan_subpoints | Either "#channel" or "nonce#channel"
hypetrain      | Twitch channel ID (integer)

When the type begins "chan_", the group will generally end "#channelname".
Note that some sockets require authentication. There is currently no API-friendly
way to authenticate, but this may be a future enhancement.

Simplified usage for common cases
---------------------------------

On the back end, if vars `ws_type` and `ws_group` are set, module `ws_sync.js`
will be automatically loaded, which will establish a websocket and call render
from the corresponding module - eg if `ws_type` is `"hypetrain"`, the module
`hypetrain.js` will be loaded, and its render() function called whenever fresh
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


Client usage
------------

Making use of ws_sync.js to establish the websocket will handle most of the
above protocol automatically. Initialize global variables thus:

    let ws_group = "some-group-name"; //For channel-based groups, end with "#channame"
    let ws_type = "some-type-name";
    let ws_code = "/static/chan_dynamics.js";
    let ws_sync = null; import('/static/ws_sync.js').then(m => ws_sync = m);

In the identified code file, provide any or all of the following exports:

    //Mandatory. Called every time there is any sort of data update.
    export function render(data) { }

Using these sockets outside of StilleBot
----------------------------------------

These websockets constitute a weak API, in that there is some small measure of
backward compatibility maintained. In particular, the hype train socket can be
used externally, so if you want to build on top of what I've made, go ahead!
