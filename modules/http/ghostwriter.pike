inherit http_websocket;
constant markdown = #"# Ghostwriter

When your channel is offline, host other channels automatically.

$$login||Hosting SomeChannel / Now Live / Channel Offline$$
{: #statusbox}

[Check hosting now](: #recheck disabled=true)

TODO: Have a nice picker for these. For now, just enter channel names, one per line.
<textarea id=channels rows=10 cols=40></textarea><br>
[Update channel list](: #updatechannels disabled=true)

<style>
#statusbox {
	max-width: max-content;
	margin: auto;
	padding: 1em;
	font-size: 125%;
	background: aliceblue; /* Colours used on startup and if not logged in */
	border: 3px solid blue;
}
#statusbox.statusidle {
	background: #ddd;
	border: 3px solid #777;
}
#statusbox.statushost {
	background: #cff;
	border: 3px solid #0ff;
}
#statusbox.statuslive {
	background: #fcf;
	border: 3px solid rebeccapurple;
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
	string login;
	if (string scopes = ensure_bcaster_token(req, "chat_login channel_editor chat:edit", req->misc->session->user->?login || "!!"))
		login = sprintf("> This feature requires Twitch chat authentication.\n>\n"
				"> [Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	return render(req, ([
		"vars": (["ws_group": !login && req->misc->session->user->login]), //If null, no connection will be established
		"login": login,
	]));
}

void got_message(string chan, string type, string message, mapping params) {
	write("Got message: %O %O %O %O\n", chan, type, message, params);
}

class IRCClient
{
	inherit Protocols.IRC.Client;
	void got_command(string what, string ... args)
	{
		//TODO: Deduplicate with connection.pike
		what = utf8_to_string(what); args[0] = utf8_to_string(args[0]); //TODO: Check if anything ever breaks because of this
		mapping(string:string) attr = ([]);
		if (has_prefix(what, "@"))
		{
			foreach (what[1..]/";", string att)
			{
				sscanf(att, "%s=%s", string name, string val);
				attr[replace(name, "-", "_")] = replace(val || "", "\\s", " ");
			}
		}
		sscanf(args[0], "%s :%s", string a, string message);
		array parts = (a || args[0]) / " ";
		if (sizeof(parts) >= 3 && (<"PRIVMSG", "NOTICE", "WHISPER", "USERNOTICE", "CLEARMSG", "CLEARCHAT">)[parts[1]])
		{
			string chan = lower_case(parts[2]);
			G->G->websocket_types->ghostwriter->got_message(chan - "#", parts[1], message, attr);
			return;
		}
		::got_command(what, @args);
	}
}

void connect(string chan, mapping info) {
	if (!has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:edit")) return;
	if (object irc = G->G->ghostwriterirc[chan]) {
		//TODO: Make sure it's still connected
		//write("Already connected to %O\n", chan);
		return;
	}
	write("Ghostwriter connecting to %O\n", chan);
	mixed ex = catch {
		object irc = IRCClient("irc.chat.twitch.tv", ([
			"nick": chan,
			"pass": "oauth:" + persist_status->path("bcaster_token")[chan],
			"connection_lost": lambda() {werror("Ghostwriter disconnecting from %O\n", chan); m_delete(G->G->ghostwriterirc, chan);},
		]));
		irc->cmd->cap("REQ","twitch.tv/tags");
		irc->cmd->cap("REQ","twitch.tv/commands");
		irc->join_channel("#" + chan);
		G->G->ghostwriterirc[chan] = irc;
	};
	if (ex) werror("%% Error connecting to IRC:\n%s\n", describe_error(ex));
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

void websocket_cmd_recheck(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Hack: Test the display
	send_updates_all(conn->group, (["status": "Hosting SomeChannel", "statustype": "host"]));
	call_out(send_updates_all, 3, conn->group, (["status": "Now Live", "statustype": "live"]));
	call_out(send_updates_all, 6, conn->group, (["status": "Channel Offline", "statustype": "idle"]));
}

protected void create(string name) {
	::create(name);
	if (!G->G->ghostwriterirc) G->G->ghostwriterirc = ([]);
	int delay = 0; //Don't hammer the server
	foreach (persist_config->path("ghostwriter"); string chan; mapping info) {
		if (sizeof(info->channels || ({ }))) call_out(connect, delay += 2, chan, info);
	}
}
