inherit http_websocket;

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
