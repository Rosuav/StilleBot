inherit http_websocket;
constant markdown = #"# Ghostwriter $$displayname$$

When your channel is offline, host other channels automatically. You can immediately
unhost and pause from this page, but if you have a stream schedule configured on
Twitch, hosting will automatically pause near the start of a scheduled stream.

$$login||Loading...$$
{: #statusbox}

[Check hosting now](: #recheck disabled=true)

<div>
Pause duration: <select disabled=true id=pausetime><option value=60>One minute</option><option value=300>Five minutes</option><option value=900 selected>Fifteen minutes</option><option value=1800>Thirty minutes</option></select>
<div id=calendar>Loading calendar...</div>
[Unhost and pause](: #pausenow disabled=true)
</div>

## Channels to autohost
1. loading...
{: #channels}

<form id=addchannel autocomplete=off>
<label>Add channel: <input name=channame></label>
[Add](: type=submit disabled=true)
</form>

<div id=autohosts_this></div>

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

constant DEFAULT_PAUSE_TIME = 900; //Ensure that this is synchronized with the <option value=N selected> in the Markdown above
mapping(string:mapping(string:mixed)) chanstate;
mapping(int:int) channel_seen_offline = ([]); //Note: Not maintained over code reload
mapping(string:mixed) schedule_check_callouts = ([]); //Cleared and rechecked over code reload
mapping(string:int) suppress_autohosting = ([]); //If a broadcaster manually unhosts or rehosts, don't change hosting for a bit.
string botid; //eg 49497888

//Mapping from target-stream-id to the channels that autohost it
//(Doesn't need to be saved, can be calculated on code update)
mapping(string:multiset(string)) autohosts_this = ([]);

/*
- Check stream schedule, and automatically unhost X seconds (default: 15 mins) before a stream
  - Use the same pause duration, both sides of the scheduled time - so if you are late starting,
    you have as much leeway after scheduled time as you have before it.
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
		"vars": (["ws_group": login ? "0" : req->misc->session->user->id]),
		"login": login,
		"displayname": !login ? "- " + req->misc->session->user->display_name : "",
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->group == "0" || msg->group == conn->session->user->?id) return 0;
	return "Not your data";
}

EventSub stream_offline = EventSub("gw_offline", "stream.offline", "1") {[string chanid, mapping event] = __ARGS__;
	//Mark the channel as just-gone-offline. That way, we won't attempt to
	//host it while it's still shutting down.
	channel_seen_offline[(int)chanid] = time();
	mapping st = chanstate[chanid];
	if (st) spawn_task(recalculate_status(chanid));
	foreach (chanstate; string id; mapping st) {
		if (st->hostingid == chanid) spawn_task(recalculate_status(id));
	}
};

void scheduled_recalculation(string chanid) {
	if (G->G->ghostwritercallouts[""] != hash_value(this)) return; //Code's been updated. Don't do anything.
	chanstate[chanid]->next_scheduled_check = 0;
	spawn_task(recalculate_status(chanid));
}
void schedule_recalculation(string chanid, array(int) targets) {
	int now = time();
	int target = min(@filter(targets, `>, now));
	int until = target - now;
	if (until < 0) return; //Including if there are no valid targets (target == 0)
	mapping st = chanstate[chanid];
	if (st->next_scheduled_check == target) return; //Already scheduled at the same time.
	if (mixed c = schedule_check_callouts[chanid]) remove_call_out(c);
	st->next_scheduled_check = target;
	schedule_check_callouts[chanid] = call_out(scheduled_recalculation, until, chanid);
}

array(string) low_recalculate_status(mapping st) {
	//1) Being live trumps all.
	if (st->uptime) return ({"live", "Now Live"});
	//2) Hosting. TODO: Distinguish Twitch autohosting from ghostwriter hosts from manual hosts (and maybe acknowledge raids too)
	if (st->hosting) return ({"host", "Hosting " + st->hosting});
	//3) Paused. Currently all pauses are shown the same way.
	//3a) Paused due to schedule
	//3b) Paused due to explicit web page interaction "unhost for X minutes"
	//TODO: Show the time a little more cleanly
	if (st->pause_until) return ({"idle", "Paused until " + ctime(st->pause_until)});
	//4) Idle
	return ({"idle", "Channel Offline"});
}
continue Concurrent.Future recalculate_status(string chanid) {
	mapping st = chanstate[chanid];
	if (!st) st = chanstate[chanid] = ([]);
	array self_live = yield(twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + chanid))->data || ({ });
	if (sizeof(self_live)) st->uptime = self_live[0]->started_at;
	else m_delete(st, "uptime");
	mapping config = persist_status->path("ghostwriter", chanid);
	int pausetime = ((int)config->pausetime || DEFAULT_PAUSE_TIME);
	array(int) next_check = ({time() + 86400}); //Maximum time that we'll ever wait between schedule checks (in case someone adds or changes)
	if (st->schedule_last_checked < next_check[0]) {
		int limit = 86400 * 7;
		array events = yield(get_stream_schedule(chanid, pausetime, 1, limit));
		if (sizeof(events)) {
			st->schedule_next_event = events[0];
			events[0]->unix_time = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", events[0]->start_time)->unix_time();
		}
		else m_delete(st, "schedule_next_event");
		st->schedule_last_checked = time();
	}
	if (mapping ev = st->schedule_next_event) {
		int pausestart = ev->unix_time - pausetime;
		next_check += ({pausestart});
		int until = ev->unix_time - time();
		if (-pausetime <= until && until <= pausetime) {
			st->pause_until = max(st->pause_until, ev->unix_time + pausetime);
		}
	}
	next_check += ({st->pause_until, suppress_autohosting[chanid]});
	schedule_recalculation(chanid, next_check);

	[st->statustype, st->status] = low_recalculate_status(st);
	send_updates_all(chanid, st);
	if (suppress_autohosting[chanid] > time()) return 0;
	array targets = config->channels || ({ });
	m_delete(st, "hostingid");
	//Clean up junk data
	if (st->pause_until) {
		int pauseleft = st->pause_until - time();
		if (pauseleft <= 0) m_delete(st, "pause_until");
	}

	if (st->pause_until) targets = ({ }); //Automatically unhost during pause time
	else if (st->hosting) {
		//Check if the hosted channel is still live
		string id = (string)yield(get_user_id(st->hosting));
		targets = ({id});
		st->hostingid = id;
		//Make sure we get notified when that channel goes offline
		stream_offline(id, (["broadcaster_user_id": (string)id]));
	}
	else if (st->statustype != "idle") {
		//If we're live, paused, or in any other yet-to-be-invented state, the only thing we want
		//to do is unhost.
		targets = ({ });
	}
	if (sizeof(targets) && mappingp(targets[0])) targets = targets->id;
	//If you have more than 100 host targets, you deserve problems. No fracturing of the array here.
	array live = ({ });
	if (st->uptime) {
		//Never host if live. However, don't spam /unhost commands either.
		if (!st->hosting) return 0;
		//Leave live empty so we'll definitely unhost.
	}
	else if (sizeof(targets)) live = yield(get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": targets])));
	string msg = "/unhost", expected = 0;
	if (sizeof(live)) {
		//If any channel has gone offline very very recently, don't autohost it.
		int mindelay = 86400;
		live = filter(live) {
			int delay = channel_seen_offline[(int)__ARGS__[0]->user_id] + 60 - time();
			if (delay > 0) mindelay = min(delay, mindelay);
			return delay <= 0;
		};
		if (mindelay && !sizeof(live)) {
			//Every live channel got filtered out. That could leave us in a weird state where,
			//due to this check, we abandon a channel that comes back online. To avoid this, we
			//recheck once the sixty-second cooldown is up.
			yield(Concurrent.resolve(1)->delay(mindelay));
			return recalculate_status(chanid);
		}

		if (sizeof(live) > 1) {
			//Reorder the live streams by the order of the original targets
			mapping byid = ([]);
			foreach (live, mapping l) byid[l->user_id] = l;
			live = map(targets, byid) - ({0});
		}
		if (sizeof(live)) {
			msg = "/host " + string_to_utf8(live[0]->user_login); //Is it possible to have a non-ASCII login??
			expected = live[0]->user_login;
		}
	}
	if (expected == st->hosting) return 0; //Including if they're both 0 (want no host, currently not hosting)
	//Currently we always take the first on the list. This may change in the future.
	write("GHOSTWRITER: Connect %O %O, send %O\n", chanid, config->chan, msg);
	object irc = yield(connect(chanid, config->chan)); //Make sure we're connected. (Mutually recursive via a long chain.)
	irc->send_message("#" + config->chan, msg);
	st->expected_host_target = expected;
	//If the host succeeds, there should be a HOSTTARGET message shortly.
}

void pause_autohost(string chanid, int target) {
	suppress_autohosting[chanid] = target;
	schedule_recalculation(chanid, ({target}));
}

void host_changed(string chanid, string target, string viewers) {
	write("GHOSTWRITER: host_changed(%O, %O, %O)\n", chanid, target, viewers);
	if (!(int)chanid) {
		//Previously this accepted channel names. In case we get old data,
		//look up the channel ID from the name and try again. (Remove this
		//code when that's not going to be a problem any more.)
		get_user_id(chanid)->then() {host_changed((string)__ARGS__[0], target, viewers);};
		return;
	}
	//Note that viewers may be "-" if we're already hosting, so don't depend on it
	mapping st = chanstate[chanid];
	if (st->hosting == target) return; //eg after reconnecting to IRC
	st->hosting = target;
	if (target == st->expected_host_target) m_delete(st, "expected_host_target");
	else if (target) pause_autohost(chanid, time() + 60); //If you manually host, disable autohost for one minute
	spawn_task(recalculate_status(chanid));
	//TODO: Purge the hook channel list of any that we don't need (those for whom autohosts_this[id] is empty or absent)
}

class IRCClient
{
	inherit Protocols.IRC.Client;
	void got_host(string message) {
		sscanf(message, "%s %s", string target, string viewers);
		if (target == "-") target = 0; //Not currently hosting
		G->G->websocket_types->ghostwriter->host_changed(options->chanid, target, viewers);
		if (object p = m_delete(options, "promise")) p->success(this);
	}
	void got_notify(string from, string type, string|void chan, string|void message, string ... extra) {
		::got_notify(from, type, chan, message, @extra);
		if (type == "HOSTTARGET") got_host(message);
		//If you're not currently hosting, there is no HOSTTARGET on startup. Once we're
		//confident that one isn't coming, notify that there is no host target.
		if (type == "ROOMSTATE" && options->promise) got_host("- -");
		if (type == "NOTICE" && sscanf(message, "%s has gone offline. Exiting host mode%s", string target, string dot) && dot == ".") {
			mapping st = chanstate[options->chanid];
			if (st->?hosting == target && st->hostingid) channel_seen_offline[(int)st->hostingid] = time();
		}
		if (type == "NOTICE" && message == "Host target cannot be changed more than 3 times every half hour.") {
			//Probably only happens while I'm testing, but ehh, whatever
			//Note that it is still legal to *unhost* for the rest of the half hour, just not host anyone.
			int target = time() + 30*60;
			G->G->websocket_types->ghostwriter->pause_autohost(options->chanid, target - target % 1800 + 3);
		}
	}
	void close() {
		if (options->promise) options->promise->failure(0);
		::close();
		remove_call_out(da_ping);
		remove_call_out(no_ping_reply);
	}
	void connection_lost() {close();}
}

Concurrent.Future connect(string chanid, string chan) {
	if (!has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:edit")) return Concurrent.reject(0);
	if (!chanstate[chanid]) chanstate[chanid] = (["statustype": "idle", "status": "Channel Offline"]);
	if (object irc = G->G->ghostwriterirc[chanid]) {
		//TODO: Make sure it's actually still connected
		write("Already connected to %O/%O, disconnecting\n", chanid, chan);
		/**/if (1) catch {irc->close();}; else
		return Concurrent.resolve(irc);
	}
	Concurrent.Promise prom = Concurrent.Promise();
	mixed ex = catch {
		object irc = IRCClient("irc.chat.twitch.tv", ([
			"nick": chan,
			"pass": "oauth:" + persist_status->path("bcaster_token")[chan],
			"promise": prom,
			"chanid": chanid,
		]));
		irc->cmd->cap("REQ","twitch.tv/commands");
		irc->join_channel("#" + chan);
		G->G->ghostwriterirc[chanid] = irc;
	};
	if (ex) {werror("%% Error connecting to IRC:\n%s\n", describe_error(ex)); return Concurrent.reject(0);}
	return prom->future();
}

continue Concurrent.Future|mapping get_state(string group) {
	if (group == "0") {
		//If you're not logged in, show the bot's autohost list as an example.
		//NOTE TO BOT OPERATORS: This *will* reveal your AH list to the world. Hack this out
		//if you're not okay with that. One easy way would be to fix botid to some other value.
		mapping config = persist_status->path("ghostwriter")[botid];
		if (!config) return ([]);
		return (["inactive": 1, "channels": config->channels || ({ })]);
	}
	array aht = ({ });
	if (multiset m = autohosts_this[group]) {
		aht = yield(get_users_info((array)m)); //Will normally yield from cache
		sort(aht->login, aht);
	}
	return (["active": 1, "channels": ({ }), "aht": aht])
		| (persist_status->path("ghostwriter")[group] || ([]))
		| (chanstate[group] || ([]));
}

continue void force_check(string chanid) {
	string chan = yield(get_user_info(chanid))->login;
	mapping irc = yield(connect(chanid, chan)); //We don't actually need the IRC object here, but forcing one to exist guarantees some checks. Avoid bug by putting it in a variable.
	yield(recalculate_status(chanid));
}

continue void force_check_all() {
	foreach (persist_status->path("ghostwriter"); string chanid;) yield(force_check(chanid));
}

void websocket_cmd_recheck(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	//Forcing a check also forces a reconnect, in case there are problems.
	if (object irc = m_delete(G->G->ghostwriterirc, conn->group)) catch {irc->close();};
	spawn_task(force_check(conn->group));
	//spawn_task(force_check_all());
}

void websocket_cmd_pause(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	string chanid = conn->group;
	mapping st = chanstate[chanid];
	mapping config = persist_status->path("ghostwriter", chanid);
	int pausetime = ((int)config->pausetime || DEFAULT_PAUSE_TIME);
	st->pause_until = time() + pausetime;
	spawn_task(recalculate_status(chanid));
	call_out(lambda() {spawn_task(G->G->websocket_types->ghostwriter->recalculate_status(chanid));}, pausetime);
}

EventSub stream_online = EventSub("gw_online", "stream.online", "1") {[string chanid, mapping event] = __ARGS__;
	write("** GW: Channel %O online: %O\nThese channels care: %O\n", chanid, event, autohosts_this[chanid]);
	mapping st = chanstate[chanid];
	if (st) spawn_task(recalculate_status(chanid));
	foreach (autohosts_this[chanid] || ([]); string id;) {
		mapping st = chanstate[id];
		write("Channel %O cares - status %O\n", persist_status->path("ghostwriter")[id]->?chan || id, st->statustype);
		if (st->statustype == "idle") spawn_task(recalculate_status(id));
	}
};

void has_channel(string chanid, string target) {
	if (!autohosts_this[target]) autohosts_this[target] = (<>);
	autohosts_this[target][chanid] = 1;
	stream_online(target, (["broadcaster_user_id": (string)target]));
	send_updates_all(target); //Could save some hassle by only updating AHT, but would need to remap to channel objects
}

void websocket_cmd_addchannel(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	if (!stringp(msg->name)) return;
	mapping config = persist_status->path("ghostwriter", conn->group);
	//TODO: Recheck all channels on add? Or do that separately?
	//Rechecking would update their avatars and display names.
	get_user_info(msg->name, "login")->then() {[mapping c] = __ARGS__;
		if (!c) return; //TODO: Report error to the user
		if (config->channels && has_value(config->channels->id, c->id)) return;
		config->channels += ({c});
		has_channel(conn->group, c->id);
		persist_status->save();
		send_updates_all(conn->group, (["channels": config->channels]));
	};
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	mapping config = persist_status->path("ghostwriter", conn->group);
	foreach ("pausetime" / " ", string key) {
		if (msg[key]) config[key] = msg[key];
	}
	persist_status->save();
	send_updates_all(conn->group, config);
}

void websocket_cmd_reorder(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	int dir = (int)msg->dir;
	if (!msg->id || !msg->dir) return;
	mapping config = persist_status->path("ghostwriter", conn->group);
	foreach (config->channels || ({ }); int i; mapping chan) {
		if (chan->id != msg->id) continue;
		//Found it.
		int dest = min(max(i + msg->dir, 0), sizeof(config->channels) - 1);
		if (dest == i) return; //No movement needed!
		//The front end will only ever send a dir of 1 or -1, so if you hack it and
		//send larger numbers, it might be a little odd. Specifically, this is a swap,
		//not multiple shifts.
		[config->channels[i], config->channels[dest]] = ({config->channels[dest], config->channels[i]});
		persist_status->save();
		send_updates_all(conn->group, (["channels": config->channels]));
		break;
	}
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)conn->group) return;
	mapping config = persist_status->path("ghostwriter", conn->group);
	if (!msg->id || !config->channels) return;
	config->channels = filter(config->channels) {return __ARGS__[0]->id != msg->id;};
	if (multiset aht = autohosts_this[msg->id]) {
		aht[conn->group] = 0;
		send_updates_all(msg->id); //As above, could just update AHT, but not worth the duplication
	}
	persist_status->save();
	send_updates_all(conn->group, (["channels": config->channels]));
}

continue Concurrent.Future migrate(string channame) {
	//Not sure why, but some names are getting into the configs.
	werror("WARNING WARNING NON-ID IN CONFIG %O\n", channame);
	int chanid = yield(get_user_id(channame));
	mapping configs = persist_status->path("ghostwriter");
	configs[(string)chanid] = m_delete(configs, channame);
	persist_status->save();
	werror("UPDATED TO ID %O\n", chanid);
}

continue Concurrent.Future no_name(string chanid) {
	//Not sure why, but some names are getting into the configs.
	werror("WARNING WARNING ID HAS NO NAME IN CONFIG %O\n", chanid);
	string channame = yield(get_user_info(chanid))->login;
	persist_status->path("ghostwriter", chanid)->chan = channame;
	persist_status->save();
	werror("UPDATED ID %O TO NAME %O\n", chanid, channame);
}

protected void create(string name) {
	::create(name);
	if (!G->G->ghostwriterirc) G->G->ghostwriterirc = ([]);
	if (!G->G->ghostwriterstate) G->G->ghostwriterstate = ([]);
	chanstate = G->G->ghostwriterstate;
	if (mapping callouts = G->G->ghostwritercallouts) {
		//Clear out the callouts, and empty the mapping so the older code sees they're gone
		foreach (indices(callouts), string chanid) if (chanid != "") remove_call_out(m_delete(callouts, chanid));
	}
	G->G->ghostwritercallouts = schedule_check_callouts = (["": hash_value(this)]);
	string botnick = persist_config["ircsettings"]->?nick;
	if (botnick) get_user_id(botnick)->then() {botid = (string)__ARGS__[0];}; //Cache the bot's user ID for the demo
	int delay = 0; //Don't hammer the server
	mapping configs = persist_status->path("ghostwriter");
	write("Configs available for %O\n", mkmapping(indices(configs), values(configs)->chan));
	if (mapping old = persist_config["ghostwriter"]) {
		//Formerly, ghostwriter configs were git-managed and keyed by login.
		//Now they are backed-up and keyed by ID.
		//We want synchronous lookup of IDs, so if we can't, queue them and leave unmigrated data.
		foreach (indices(old), string chan) {
			if ((int)chan) {configs[chan] = m_delete(old, chan); continue;}
			if (!G->G->user_info[chan]) {
				//Don't know the ID. Look it up (for the cache), leave it unmigrated.
				werror("WARNING: Unmigrated Ghostwriter configs for %O - update again to check\n", chan);
				get_user_id(chan);
				continue;
			}
			string chanid = (string)G->G->user_info[chan]->id;
			if (configs[chanid] && sizeof(configs[chanid])) {
				werror("WARNING: Unmerged Ghostwriter configs for %O and %O\n", chan, chanid);
				continue;
			}
			configs[chanid] = m_delete(old, chan);
			configs[chanid]->chan = chan;
		}
		if (!sizeof(old)) m_delete(persist_config, "ghostwriter");
		else persist_config->save();
		persist_status->save();
	}
	if (string data = Stdio.read_file("lastnightbackup.json")) {
		write("RESTORING CONTENT\n");
		foreach (Standards.JSON.decode_utf8(data)->ghostwriter; string chanid; mapping cfg) {
			if (!sizeof(cfg)) continue;
			if (!(int)chanid) {write("Non-integer key skipped: %O\n", chanid); continue;}
			if (configs[chanid] && sizeof(configs[chanid])) {
				if (!sizeof(configs[chanid]->channels || ({ })) && sizeof(cfg->channels || ({ }))) {
					write("Merging in channels only: %O\n", chanid);
					configs[chanid]->channels = cfg->channels;
				}
				write("Already has content, not merging: %O\n", chanid);
				write("Have: %O\nRestore: %O\n", indices(configs[chanid]), indices(cfg));
				continue;
			}
			configs[chanid] = cfg;
			persist_status->save();
			write("Restored from backup: %O\n", chanid);
		}
	}
	foreach (configs; string chanid; mapping info) {
		if (!(int)chanid) {spawn_task(migrate(chanid)); continue;}
		if (!info->chan) {spawn_task(no_name(chanid)); continue;}
		if (!info->?channels || !sizeof(info->channels)) continue;
		call_out(connect, delay += 2, chanid, info->chan);
		has_channel(chanid, info->channels->id[*]);
		if (int t = chanstate[chanid]->?next_scheduled_check) {
			t -= time();
			if (t >= 0) schedule_check_callouts[chanid] = call_out(scheduled_recalculation, t, chanid);
		}
	}
}
