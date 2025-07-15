API access
==========

As of 20250715, this is *plans for* API access, this isn't implemented yet.

TODO: Support general access via ID, eg https://mustardmine.com/channels/49497888/monitors
This will be encouraged for API users but not otherwise; if a GET request is
sent to the ID, redirect to the username.

## Connecting

All API requests may be sent via either HTTP POST or a websocket. POST is more
convenient for single or occasional requests; a websocket allows more requests
without reauthenticating.

A request will always be a JSON object with a "cmd" attribute. For example:

   {"cmd":"serverstatus"}

You may optionally include a `"requestid"`, which will be echoed back in the
response. This has no effect but may be used for your own synchronization.
(More useful with a websocket than a POST request.)

The response will also always be JSON. If it includes an `"error"`, it will be
a non-empty string and will signal failure.

### POST requests

Endpoint: https://{node}.mustardmine.com/channels/{channel}/api
Node is optional (can use https://mustardmine.com) but may improve performance
Headers:
* Authorization: Bearer "token goes here"
* Content-Type: application/json

The body of the request is the JSON command object. The response will also be
JSON and will be the response to this message.


### WebSockets


Endpoint: https://{node}.mustardmine.com/ws
Node is also optional, but you must respect redirects.
At any time, you may receive a disconnect signal:
`{"cmd": "*DC*", "redirect": "gideon.mustardmine.com"}`
On receipt of this message, you will need to reconnect to the specified node.
If there is no redirect given, wait some time and then reconnect to the
default endpoint.

All websocket frames should be text, and contain JSON-encoded objects.

## Available commands

### serverstatus

   {"cmd": "serverstatus"}
   
   {"active_bot": "sikorsky.mustardmine.com"}

No additional parameters. The active bot will be the DNS name or IP address
of the bot node that will serve your requests. Sending API requests to this
bot may improve response times.

### send

   {"cmd": "send", "message": "Hello from the API!"}
   
   {"messageids": ["2cfeda56-4b7d-4d76-9ad8-9e564166cc39"]}

Send a message in the channel. The given message may be anything acceptable
to the command editor; use "Raw" mode to see the JSON for any command.  This
can be used to update variables, perform bot actions, send messages, wield
a mod sword, or anything else that could be done in a command, trigger, etc.

The returned message IDs, if any, can be used to chain messages into a thread,
or delete the message, etc. Currently at most one such ID will be returned(?).

### mustard

   {"cmd": "mustard", "mustard": "$counter$ += 1"}
   
   {"message": {"dest": "/set", "destcfg": "add", "message": "1", "target": "counter"}}

or

   {"cmd": "mustard", "message": {"dest": "/set", "destcfg": "add", "message": "1", "target": "counter"}}
   
   {"mustard": "$counter$ += \"1\""}

Compile MustardScript to JSON, or represent a JSON command in MustardScript.
