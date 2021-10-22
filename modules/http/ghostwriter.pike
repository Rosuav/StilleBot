inherit http_websocket;
constant markdown = #"# Ghostwriter

When your channel is offline, host other channels automatically.

$$login$$

TODO: Have a nice picker for these. For now, just enter channel names, one per line.
<textarea id=channels rows=10 cols=40></textarea><br>
[Update channel list](: #updatechannels disabled=true)

<style>
#loginbox {
	max-width: max-content;
	background: aliceblue;
	border: 3px solid blue;
	margin: auto;
	padding: 1em;
	font-size: 125%;
}
</style>
";

/*
- Require login for functionality, but give full deets
- Event-based, but can be pinged via the web site "re-check". Also check on bot startup.
- Three states: Online, Hosting, Idle
- If Online, next event is Stream Offline (self)
- If Hosting, next event is Stream Offline (host target)
- If Idle, next event is Stream Online (self or any target)
- Note that Stream Offline may need to track any channel, not just a registered target
- Would probably need to spin up an altvoice (so this is a poltergeist) to see host status and send host commands
- Check stream schedule, and automatically unhost X seconds (default: 15 mins) before a stream
*/

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string login = "";
	if (string scopes = ensure_bcaster_token(req, "chat:edit", req->misc->session->user->?login || "!!"))
		login = sprintf("> This feature requires Twitch chat authentication.\n>\n"
				"> [Grant permission](: .twitchlogin data-scopes=@%s@)\n"
				"{: #loginbox}", scopes);
	return render(req, ([
		"vars": (["ws_group": login == "" && req->misc->session->user->login]), //If null, no connection will be established
		"login": login,
	]));
}

mapping get_state(string group) {return persist_config->path("ghostwriter")[group] || ([]);}

void websocket_cmd_setchannels(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	if (!arrayp(msg->channels)) return;
	mapping config = persist_config->path("ghostwriter", conn->group);
	array chan = map(msg->channels) {[mapping c] = __ARGS__;
		if (!mappingp(c)) return 0;
		c->name = String.trim(c->name || "");
		if (c->name == "") return;
		//TODO: Look up the channel and make sure it's valid
		return c;
	};
	chan -= ({0});
	config->channels = chan;
	persist_config->save();
	send_updates_all(conn->group, (["channels": chan]));
}
