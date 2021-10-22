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

mapping get_state(string group, string|void id) {return ([]);}
