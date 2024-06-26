WebSockets in the Mustard Mine
==============================

Mustard Mine's web interface relies heavily on websockets for real-time sharing
of synchronized data. Herein are some technical notes; you don't need any of
this information to use the bot, but if you're interested in making third-party
integrations, this may be of value.

Every established websocket has two identifying values: a type and a group.
The type is a keyword, with valid values being defined in the code by modules
that inherit websocket_handler; any other values are errors. The group is
either a string or an integer, and its meaning depends on the type.

Example type   | Corresponding groups
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

(There are other type/group pairs available; explore the source code or experiment.)
When the type begins "chan_", the group will generally end "#channelid".
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

    let ws_group = "some-group-name"; //For channel-based groups, end with "#channelid"
    let ws_type = "some-type-name";
    let ws_code = "/static/chan_dynamics.js";
    let ws_sync = null; import('/static/ws_sync.js').then(m => ws_sync = m);

In the identified code file, provide any or all of the following exports:

    //Mandatory. Called every time there is any sort of data update.
    export function render(data) { }
    //To be notified when {"cmd": "FOO"} is received from the server:
    export function sockmsg_FOO(msg) { }
    //For rendering of individual items, including partial updates:
    export const autorender = {
      //The most common is "item", but anything is supported. Have more
      //than one of these sets to automatically render multiple arrays.
      item_parent: DOM("#some_element"),
      item(it) {return LI({"data-id": it.id}, it.name);},
      item_empty() { }, //Called whenever there are no items to display
    }
    //Absent is equivalent to empty. All items are optional.
    export const ws_config = {
      //Silence some or all of the console messages
      //  conn - connect/disconnect tracing
      //  msg - known incoming messages
      //  unkmsg - unknown incoming messages
      //  send - outgoing messages (only valid on the default handler)
      quiet: {conn: 1},
    }

For compatibility with the previous specification, autorender can also be
provided as three separate exports, if autorender itself is absent:

    export const render_parent = DOM("#some_element");
    export function render_item(it) {return LI({"data-id": it.id, it.name);}
    export function render_empty() { }

The empty renderer is optional, but if provided, will be called (a) when a
full update gives an empty array of items, and (b) when a single-item render
removes the last item. Its return value, if any, should be a DOM element; it
will be removed upon the next non-empty render. This element may be inside or
outside the item_parent.

Elements returned from the item renderer will have their data-id attribute set
automatically to the ID of the corresponding element.

Using these sockets outside of Mustard Mine
-------------------------------------------

These websockets constitute a weak API, in that there is some small measure of
backward compatibility maintained. In particular, the hype train socket can be
used externally, so if you want to build on top of what I've made, go ahead!

The easiest sockets to listen on would probably be chan_monitors and
chan_alertbox, using their nonce#channel groups for read-only access (this is
how the browser source inside OBS gets its signals). Third party integrations
would be able to receive notifications from Mustard Mine when things happen.
