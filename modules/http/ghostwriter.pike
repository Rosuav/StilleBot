inherit http_websocket;
constant markdown = #"# Ghostwriter $$displayname$$

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

mapping(string:mapping(string:mixed)) chanstate;

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
- TODO: Allow host overriding if a higher-priority target goes live
  - This would add an event while Hosting: "stream online (self or any higher target)"
  - Would also change the logic in recalculate_status to check even if hosting
*/

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string login;
	if (string scopes = ensure_bcaster_token(req, "chat_login channel_editor chat:edit", req->misc->session->user->?login || "!!"))
		login = sprintf("> This feature requires Twitch chat authentication.\n>\n"
				"> [Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	return render(req, ([
		"vars": (["ws_group": !login && req->misc->session->user->login]), //If null, no connection will be established
		"login": login,
		"displayname": !login ? "- " + req->misc->session->user->display_name : "",
	]));
}

continue Concurrent.Future findhost(string chan, array(mapping) targets) {
	//If you have more than 100 host targets, you deserve problems. No fracturing of the array here.
	write("Probing %O\n", targets);
	array live = yield(get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_login": targets->name])));
	write("Live: %O\n", live);
	if (!sizeof(live)) return 0; //Nothing to do, nobody live.
	//Reorder the live streams by the order of the original targets
	/* Requires the IDs to be stored.
	mapping byid = ([]);
	foreach (live, mapping st) byid[live->user_id] = live;
	live = map(targets->id, byid) - ({0});
	if (!sizeof(live)) return 0; //Somehow we lost everyone?
	*/
	//Currently we always take the first on the list. This may change in the future.
	object irc = yield(connect(chan)); //Make sure we're connected. (Mutually recursive via a long chain.)
	write("Connected\n");
	irc->send_message("#" + chan, "/host " + string_to_utf8(live[0]->user_login)); //Is it possible to have a non-ASCII login??
	//If the host succeeds, there should be a HOSTTARGET message shortly.
	write("Got live: %O\n", live);
}

array(string) low_recalculate_status(mapping st) {
	//1) Being live trumps all.
	if (st->uptime) return ({"live", "Now Live"});
	//2) Hosting. TODO: Distinguish Twitch autohosting from ghostwriter hosts from manual hosts (and maybe acknowledge raids too)
	if (st->hosting) return ({"host", "Hosting " + st->hosting});
	//3) Paused.
	//3a) TODO: Paused due to schedule
	//3b) TODO: Paused due to explicit web page interaction "unhost for X minutes"
	//4) Idle
	return ({"idle", "Channel Offline"});
}
void recalculate_status(string chan) {
	mapping st = chanstate[chan];
	[st->statustype, st->status] = low_recalculate_status(st);
	send_updates_all(chan, st); //Note: doesn't update configs, so it won't trample all over a half-done change in a client
	if (st->statustype == "idle") {
		mapping config = persist_config->path("ghostwriter", chan);
		array targets = config->channels || ({ });
		if (sizeof(targets)) spawn_task(findhost(chan, targets));
	}
}

void host_changed(string chan, string target, string viewers) {
	//Note that viewers may be "-" if we're already hosting, so don't depend on it
	if (chanstate[chan]->hosting == target) return; //eg after reconnecting to IRC
	write("Host changed: %O -> %O\n", chan, target);
	chanstate[chan]->hosting = target;
	recalculate_status(chan);
}

class IRCClient
{
	inherit Protocols.IRC.Client;
	void got_host(string chan, string message) {
		sscanf(message, "%s %s", string target, string viewers);
		if (target == "-") target = 0; //Not currently hosting
		G->G->websocket_types->ghostwriter->host_changed(chan - "#", target, viewers);
		if (object p = m_delete(options, "promise")) p->success(this);
	}
	void got_notify(string from, string type, string|void chan, string|void message, string ... extra) {
		::got_notify(from, type, chan, message, @extra);
		if (type == "HOSTTARGET") got_host(chan, message);
		//If you're not currently hosting, there is no HOSTTARGET on startup. Once we're
		//confident that one isn't coming, notify that there is no host target.
		if (type == "ROOMSTATE" && options->promise) got_host(chan, "- -");
	}
	void close() {
		if (options->promise) options->promise->failure(0);
		::close();
		remove_call_out(da_ping);
		remove_call_out(no_ping_reply);
	}
	void connection_lost() {close();}
}

Concurrent.Future connect(string chan) {
	if (!has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:edit")) return Concurrent.reject(0);
	if (!chanstate[chan]) chanstate[chan] = (["statustype": "idle", "status": "Channel Offline"]);
	if (object irc = G->G->ghostwriterirc[chan]) {
		//TODO: Make sure it's actually still connected
		//write("Already connected to %O\n", chan);
		//**/if (1) catch {irc->close();}; else
		return Concurrent.resolve(irc);
	}
	write("Ghostwriter connecting to %O\n", chan);
	Concurrent.Promise prom = Concurrent.Promise();
	mixed ex = catch {
		object irc = IRCClient("irc.chat.twitch.tv", ([
			"nick": chan,
			"pass": "oauth:" + persist_status->path("bcaster_token")[chan],
			"promise": prom,
		]));
		irc->cmd->cap("REQ","twitch.tv/commands");
		irc->join_channel("#" + chan);
		G->G->ghostwriterirc[chan] = irc;
	};
	if (ex) {werror("%% Error connecting to IRC:\n%s\n", describe_error(ex)); return Concurrent.reject(0);}
	return prom->future();
}

mapping get_state(string group) {return (persist_config->path("ghostwriter")[group] || ([])) | (chanstate[group] || ([]));}

continue void force_check(string chan) {
	[object irc, mapping data] = yield(Concurrent.all(connect(chan),
		twitch_api_request("https://api.twitch.tv/helix/streams?user_login=" + chan)));
	//We don't actually need the IRC object here, just that one has to exist.
	mapping st = chanstate[chan];
	if (!sizeof(data->data)) m_delete(st, "uptime");
	else st->uptime = data->data[0]->started_at;
	recalculate_status(chan);
}

void websocket_cmd_recheck(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Forcing a check also forces a reconnect, in case there are problems.
	if (object irc = m_delete(G->G->ghostwriterirc, conn->group)) catch {irc->close();};
	spawn_task(force_check(conn->group));
}

//TODO: Maintain a mapping from target-stream-id to array of channels that autohost it
//(Doesn't need to be saved, can be calculated on code update)
//On stream online, for each channel autohosting it, if idle, host it.
//On stream offline, for each channel autohosting it, if hosting it, recheck.
//EventSub stream_online = EventSub("online", "stream.online", "1") {Stdio.append_file("evthook.log", sprintf("EVENT: Stream online [%d, %O]: %O\n", time(), @__ARGS__));};
//EventSub stream_offline = EventSub("offline", "stream.offline", "1") {Stdio.append_file("evthook.log", sprintf("EVENT: Stream offline [%d, %O]: %O\n", time(), @__ARGS__));};
		//stream_online(chan, (["broadcaster_user_id": (string)userid])); //These two don't actually give us any benefit.
		//stream_offline(chan, (["broadcaster_user_id": (string)userid]));

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

protected void create(string name) {
	::create(name);
	if (!G->G->ghostwriterirc) G->G->ghostwriterirc = ([]);
	if (!G->G->ghostwriterstate) G->G->ghostwriterstate = ([]);
	chanstate = G->G->ghostwriterstate;
	int delay = 0; //Don't hammer the server
	foreach (persist_config->path("ghostwriter"); string chan; mapping info) {
		if (sizeof(info->channels || ({ }))) call_out(connect, delay += 2, chan);
	}
}
