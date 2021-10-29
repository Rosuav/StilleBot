inherit http_websocket;
constant markdown = #"# Ghostwriter $$displayname$$

When your channel is offline, host other channels automatically.

$$login||Loading...$$
{: #statusbox}

[Check hosting now](: #recheck disabled=true)

Pause duration: <select disabled=true id=pausetime><option value=60>One minute</option><option value=300>Five minutes</option><option value=900 selected>Fifteen minutes</option><option value=1800>Thirty minutes</option></select>
[Unhost and pause](: #pausenow disabled=true)

## Channels to autohost
1. loading...
{: #channels}

<form id=addchannel autocomplete=off>
<label>Add channel: <input name=channame></label>
[Add](: type=submit disabled=true)
</form>

<style>
.avatar {max-width: 40px; vertical-align: middle; margin: 0 8px;}
#channels button {min-width: 25px; height: 25px; margin: 0 5px;}
/* Hide buttons that wouldn't have any effect */
#channels li:first-of-type .moveup {visibility: hidden;}
#channels li:last-of-type .movedn {visibility: hidden;}
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
- Check stream schedule, and automatically unhost X seconds (default: 15 mins) before a stream
  - Use the same pause duration, both sides of the scheduled time - so if you are late starting,
    you have as much leeway after scheduled time as you have before it.
- TODO: Allow host overriding if a higher-priority target goes live
  - This would add an event while Hosting: "stream online (self or any higher target)"
  - Would also change the logic in recalculate_status to check even if hosting
- FIXME: Connection group is your login, not your ID. This applies also to your configs.
*/

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string login;
	if (string scopes = ensure_bcaster_token(req, "chat_login channel_editor chat:edit", req->misc->session->user->?login || "!!"))
		login = sprintf("> This feature requires Twitch chat authentication.\n>\n"
				"> [Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	return render(req, ([
		"vars": (["ws_group": login ? "0" : req->misc->session->user->login]),
		"login": login,
		"displayname": !login ? "- " + req->misc->session->user->display_name : "",
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->group == "0" || msg->group == conn->session->user->?login) return 0;
	return "Not your data";
}

EventSub stream_offline = EventSub("gw_offline", "stream.offline", "1") {[string chanid, mapping event] = __ARGS__;
	write("** GW: Channel %O offline: %O\n", chanid, event);
	mapping st = chanstate[event->broadcaster_user_login];
	if (st) spawn_task(recalculate_status(event->broadcaster_user_login));
	foreach (chanstate; string chan; mapping st) {
		if (st->hostingid == chanid) spawn_task(recalculate_status(chan));
	}
};

array(string) low_recalculate_status(mapping st) {
	//1) Being live trumps all.
	if (st->uptime) return ({"live", "Now Live"});
	//2) Hosting. TODO: Distinguish Twitch autohosting from ghostwriter hosts from manual hosts (and maybe acknowledge raids too)
	if (st->hosting) return ({"host", "Hosting " + st->hosting});
	//3) Paused.
	//3a) TODO: Paused due to schedule
	//3b) Paused due to explicit web page interaction "unhost for X minutes"
	//TODO: Show the time a little more cleanly
	if (st->pause_until) return ({"idle", "Paused until " + ctime(st->pause_until)});
	//4) Idle
	return ({"idle", "Channel Offline"});
}
continue Concurrent.Future recalculate_status(string chan) {
	mapping st = chanstate[chan];
	[st->statustype, st->status] = low_recalculate_status(st);
	send_updates_all(chan, st);
	mapping config = persist_config->path("ghostwriter", chan);
	array targets = config->channels || ({ });
	//If we're hitting the API too much, rate-limit this check (eg once per five mins), but remove
	//the flag saying recent check any time the user explicitly forces a check.
	//TODO: Figure out where we're going to retain IDs since we'll defo need them for this
	//mapping sched = yield(twitch_api_request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id + "&first=5"));
	m_delete(st, "hostingid");
	if (st->pause_until) {
		int pauseleft = st->pause_until - time();
		write("Pause left: %O\n", pauseleft);
		if (pauseleft <= 0) m_delete(st, "pause_until");
		else targets = ({ }); //Automatically unhost during pause time
	}
	else if (st->hosting) {
		//Check if the hosted channel is still live
		string id = (string)yield(get_user_id(st->hosting));
		targets = ({id});
		st->hostingid = id;
		//Make sure we get notified when that channel goes offline
		stream_offline(id, (["broadcaster_user_id": (string)id]));
	}
	else if (st->statustype == "idle") targets = targets->id;
	else {
		//If we're live, paused, or in any other yet-to-be-invented state, the only thing we want
		//to do is unhost.
		targets = ({ });
	}
	//If you have more than 100 host targets, you deserve problems. No fracturing of the array here.
	write("Probing %O\n", targets);
	array live = ({ });
	if (sizeof(targets)) live = yield(get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": targets])));
	write("Live: %O\n", live);
	string msg = "/unhost";
	if (sizeof(live) > 1) {
		//Reorder the live streams by the order of the original targets
		mapping byid = ([]);
		foreach (live, mapping st) byid[live->user_id] = live;
		live = map(targets, byid) - ({0});
	}
	if (sizeof(live)) msg = "/host " + string_to_utf8(live[0]->user_login); //Is it possible to have a non-ASCII login??
	//Currently we always take the first on the list. This may change in the future.
	object irc = yield(connect(chan)); //Make sure we're connected. (Mutually recursive via a long chain.)
	write("Connected\n");
	irc->send_message("#" + chan, msg);
	//If the host succeeds, there should be a HOSTTARGET message shortly.
	write("Got live: %O\n", live);
}

void host_changed(string chan, string target, string viewers) {
	//Note that viewers may be "-" if we're already hosting, so don't depend on it
	if (chanstate[chan]->hosting == target) return; //eg after reconnecting to IRC
	write("Host changed: %O -> %O\n", chan, target);
	chanstate[chan]->hosting = target;
	spawn_task(recalculate_status(chan));
	//TODO: Purge the hook channel list of any that we don't need (those for whom autohosts_this[id] is empty or absent)
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

mapping get_state(string group) {
	if (group == "0") {
		//If you're not logged in, show the bot's autohost list as an example.
		//NOTE TO BOT OPERATORS: This *will* reveal your AH list to the world. Hack this out
		//if you're not okay with that.
		mapping config = persist_config->path("ghostwriter")[persist_config["ircsettings"]->nick];
		if (!config) return ([]);
		return (["inactive": 1, "channels": config->channels || ({ })]);
	}
	return (["active": 1, "channels": ({ })]) | (persist_config->path("ghostwriter")[group] || ([])) | (chanstate[group] || ([]));
}

continue void force_check(string chan) {
	[object irc, mapping data] = yield(Concurrent.all(connect(chan),
		twitch_api_request("https://api.twitch.tv/helix/streams?user_login=" + chan)));
	//We don't actually need the IRC object here, just that one has to exist.
	mapping st = chanstate[chan];
	if (!sizeof(data->data)) m_delete(st, "uptime");
	else st->uptime = data->data[0]->started_at;
	yield(recalculate_status(chan));
}

void websocket_cmd_recheck(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	//Forcing a check also forces a reconnect, in case there are problems.
	if (object irc = m_delete(G->G->ghostwriterirc, conn->group)) catch {irc->close();};
	spawn_task(force_check(conn->group));
}

void websocket_cmd_pause(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	string chan = conn->group;
	mapping st = chanstate[chan];
	mapping config = persist_config->path("ghostwriter", chan);
	int pausetime = ((int)config->pausetime || 900);
	st->pause_until = time() + pausetime;
	spawn_task(recalculate_status(chan));
	call_out(lambda() {spawn_task(G->G->websocket_types->ghostwriter->recalculate_status(chan));}, pausetime);
}

//Mapping from target-stream-id to the channels that autohost it
//(Doesn't need to be saved, can be calculated on code update)
mapping(string:multiset(string)) autohosts_this = ([]);
EventSub stream_online = EventSub("gw_online", "stream.online", "1") {[string chanid, mapping event] = __ARGS__;
	write("** GW: Channel %O online: %O\nThese channels care: %O\n", chanid, event, autohosts_this[chanid]);
	mapping st = chanstate[event->broadcaster_user_login];
	if (st) spawn_task(recalculate_status(event->broadcaster_user_login));
	foreach (autohosts_this[chanid]; string chan;) {
		mapping st = chanstate[chan];
		write("Channel %O cares - status %O\n", chan, st->statustype);
		if (st->statustype == "idle") spawn_task(recalculate_status(chan));
	}
};

void has_channel(string chan, string target) {
	if (!autohosts_this[target]) autohosts_this[target] = (<>);
	autohosts_this[target][chan] = 1;
	stream_online(target, (["broadcaster_user_id": (string)target]));
}

void websocket_cmd_addchannel(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	if (!stringp(msg->name)) return;
	mapping config = persist_config->path("ghostwriter", conn->group);
	//TODO: Recheck all channels on add? Or do that separately?
	//Rechecking would update their avatars and display names.
	get_user_info(msg->name, "login")->then() {[mapping c] = __ARGS__;
		if (!c) return; //TODO: Report error to the user
		if (config->channels && has_value(config->channels->id, c->id)) return;
		config->channels += ({c});
		has_channel(conn->group, c->id);
		persist_config->save();
		send_updates_all(conn->group, (["channels": config->channels]));
	};
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	mapping config = persist_config->path("ghostwriter", conn->group);
	foreach ("pausetime" / " ", string key) {
		if (msg[key]) config[key] = msg[key];
	}
	persist_config->save();
	send_updates_all(conn->group, config);
}

void websocket_cmd_reorder(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	int dir = (int)msg->dir;
	if (!msg->id || !msg->dir) return;
	mapping config = persist_config->path("ghostwriter", conn->group);
	foreach (config->channels || ({ }); int i; mapping chan) {
		if (chan->id != msg->id) continue;
		//Found it.
		int dest = min(max(i + msg->dir, 0), sizeof(config->channels) - 1);
		if (dest == i) return; //No movement needed!
		//The front end will only ever send a dir of 1 or -1, so if you hack it and
		//send larger numbers, it might be a little odd. Specifically, this is a swap,
		//not multiple shifts.
		[config->channels[i], config->channels[dest]] = ({config->channels[dest], config->channels[i]});
		persist_config->save();
		send_updates_all(conn->group, (["channels": config->channels]));
		break;
	}
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->group || conn->group == "0") return;
	mapping config = persist_config->path("ghostwriter", conn->group);
	if (!msg->id || !config->channels) return;
	config->channels = filter(config->channels) {return __ARGS__[0]->id != msg->id;};
	if (multiset aht = autohosts_this[msg->id]) aht[conn->group] = 0;
	persist_config->save();
	send_updates_all(conn->group, (["channels": config->channels]));
}

protected void create(string name) {
	::create(name);
	if (!G->G->ghostwriterirc) G->G->ghostwriterirc = ([]);
	if (!G->G->ghostwriterstate) G->G->ghostwriterstate = ([]);
	chanstate = G->G->ghostwriterstate;
	int delay = 0; //Don't hammer the server
	foreach (persist_config->path("ghostwriter"); string chan; mapping info) {
		if (!info->channels || !sizeof(info->channels)) continue;
		call_out(connect, delay += 2, chan);
		has_channel(chan, info->channels->id[*]);
	}
}
