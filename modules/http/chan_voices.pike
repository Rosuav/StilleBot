inherit http_websocket;
constant markdown = #"
# Available voices for $$channel$$

Normally the channel bot will speak using its own voice, as defined by the
bot's login. However, for certain situations, it is preferable to allow the bot
to speak using some other voice. This requires authentication as the new voice,
which is not necessarily who you're currently logged in as.

You must first be a channel moderator to enable this, and then must also have
the credentials for the voice you plan to use (be it the broadcaster or some
dedicated bot account).

Name        | Description/purpose | -
------------|---------------------|----
-           | Loading...
{: #voices}

[Add new voice](:#addvoice)
";
//Note that, in theory, multiple voice support could be done without an HTTP interface.
//It would be fiddly to set up, though, so I'm not going to try to support it at this
//stage. Maybe in the future. For now, if you're working without the web interface, you
//will need to manually set a "voice" on a command, and you'll need to manually craft
//the persist_status entries for the login.

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

mapping get_chan_state(object channel, string grp, string|void id) {
	return (["items": ({ })]);
}
