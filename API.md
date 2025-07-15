API access
==========

As of 20250715, this is *plans for* API access, this isn't implemented yet.

TODO: Support general access via ID, eg https://mustardmine.com/channels/49497888/monitors
This will be encouraged for API users but not otherwise; if a GET request is
sent to the ID, redirect to the username.

POST endpoint: https://{node}.mustardmine.com/channels/{channel}/api
Node is optional (can use https://mustardmine.com) but may improve performance

Websocket endpoint: https://{node}.mustardmine.com/ws
Node is also optional, but you must respect redirects.
