inherit http_websocket;
inherit hook;
inherit annotated;
constant markdown = #"# VLC integration

(loading...)
{:#nowplaying}

> ### Recently played
> * not loaded
> {:#recent}
>
{: tag=details $$showrecents||$$}

<!-- -->

> ### Lyrics (beta)
> * loading...
> {:#lyrics}
>
> <audio controls muted id=karaoke><track default kind=captions label=Lyrics></audio><br>
> [Synchronize](:#karaoke_sync)
{: tag=details}

<style>
#nowplaying {
	background: #ddffdd;
	border: 1px solid #007700;
	font-size: larger;
}
#recent li:nth-child(even) {
	background: #ddffee;
}
#recent li:nth-child(odd) {
	background: #eeffdd;
}
details {border: 1px solid transparent;} /* I love 'solid transparent', ngl */
details#config {
	padding: 0 1.5em;
	border: 1px solid rebeccapurple;
}
#config summary {
	margin: 0 -1.5em;
}

#lyrics {
	list-style-type: none;
	width: fit-content;
	max-height: 5.5em;
	overflow-y: scroll;
	padding: 0 1em;
}
/* Hackery and dark magic. We want scrollIntoView to ensure that the next line of
lyrics is visible too, so the element needs to be a bit taller than it looks. But
that extra height has to NOT be coloured by the .active class, so it's done as a
white border. Of course, we need the next lyric line to be drawn over that white
border, hence the negative margin. To avoid losing the first lyric line above the
top of the screen, we remove its margin; and to avoid having a gap at the bottom,
we remove the border from the last one. Although, on analysis, it looks fine with
the gap at the bottom (makes it clear that we're done), so I'm actually keeping a
white border on the last list item. */
#lyrics li {
	transition: all 1s;
	border-bottom: 1.25em solid #eee;
	margin-top: -1.25em;
}
#lyrics li:first-child {margin-top: 0;}
/* #lyrics li:last-child {border-bottom-width: 0;} */
#lyrics .active {
	background: #a0f0c0;
	transition: background 0s;
}
</style>

$$modconfig||$$

$$save_or_login||$$
";

/* Am getting some duplicated messages, sometimes with "paused" followed by "playing".
Theory: VLC is announcing status of "loading", the Lua script is announcing that as "not
playing", and Pike is interpreting that as "paused". Then when the file finishes loading,
it gets the "playing" status, and pushes the notif through.

Solution #1: If "loading", ignore the status change; but that's supposed to be already
happening. Check what the actual values are, and see if the "4" needs changing.

Solution #2: If we change from playing to paused to playing inside 2s, suppress text. This
would be done in the default command, NOT here in the code.
*/

//Additional Markdown code added if, and only if, you're logged in as a mod
constant MODCONFIG = #"> ### Configuration
> * <chatnotif>
> * [Download Lua script](vlc?lua) - put it into .local/share/vlc/lua/extensions (create that dir if needed)
> * [Reset credentials](:#authreset) - will deauthenticate any previously-downloaded Lua script
>
> Describe a collection of music based on its directory to have a \"block\"
> in the special trigger.
>
> Path | Description | &nbsp;
> -----|-------------|-------
> -    | -
> {:#blocks}
>
> Directory names will appear above when they are first played.
>
{: #config tag=details open=1}

<style>
/* Expand the inputs to share available space */
#blocks, #blocks input {width: 100%;}
/* But the Save buttons don't need any spare space. For some reason,
this works. I don't understand, but I'll take it. */
#blocks thead th:last-of-type {width: 0;}
</style>
";
@retain: mapping vlc_status = ([]);

//Create (if necessary) and return the VLC Auth Token
string auth_token(object channel) {
	if (string t = channel->config->vlcauthtoken) return t;
	persist_config->save();
	return channel->config->vlcauthtoken = String.string2hex(random_string(12));
}

void sendstatus(object channel) {
	mapping status = vlc_status[channel->name] || ([]);
	channel->trigger_special("!musictrack", (["user": "VLC"]), ([
		"{playing}": (string)status->playing,
		"{desc}": status->current || "",
		"{blockpath}": status->curblock || "",
		"{block}": status->curblockdesc || "",
		"{track}": status->curtrack || "",
	]));
	//Note: We set the $vlcplaying$ and $vlccurtrack$ variables after the special goes through.
	//That way, if you want to check for a change, you can, but otherwise, the vars are just
	//there automatically.
	channel->set_variable("vlcplaying", (string)status->playing, "set");
	channel->set_variable("vlccurtrack", status->current || "", "set");
	send_updates_all(channel->name);
	send_updates_all("blocks" + channel->name);
	if (channel->config->vlcauthtoken) send_updates_all(channel->config->vlcauthtoken + channel->name);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	object channel = req->misc->channel;
	if (req->misc->is_mod && req->variables->makespecial) {
		//Note that this option isn't made obvious if you already have the command,
		//but we won't stop you from using it if you do so manually. It'll overwrite.
		G->G->enableable_modules->specials->enable_feature(channel, "songannounce", 1);
		return redirect("vlc");
	}
	if (req->misc->is_mod && !req->misc->session->fake && req->variables->lua) {
		mapping cfg = persist_config["ircsettings"];
		mapping resp = render_template("vlcstillebot.lua", ([
			"url": cfg->http_address + req->not_query,
			"auth": auth_token(channel),
		]));
		resp->type = "application/x-lua";
		resp->extra_heads = (["Content-disposition": "attachment; filename=vlcstillebot.lua"]);
		return resp;
	}
	mapping status = vlc_status[channel->name];
	if (req->variables->auth && req->variables->auth == channel->config->vlcauthtoken) {
		//It could be a valid VLC signal.
		if (!status) status = vlc_status[channel->name] = ([]);
		req->variables->auth = "(correct)"; //werror("%sGot VLC notification: %O\n", ctime(time()), req->variables);
		if (req->variables->shutdown) req->variables->status = "shutdown";
		int send = 0;
		if (string uri = req->variables->now_playing) {
			catch {uri = utf8_to_string(uri);}; //If it's not UTF-8, pretend it's Latin-1
			status->cururi = uri;
			if (req->variables->usec) {
				//We've been told the current position. Since time has a nasty habit of
				//marching on, we instead record the time_t when the track "notionally
				//started". This isn't necessarily the time the track ACTUALLY started,
				//but if the track has been playing constantly, it will be close.
				//Note that we assume here that we are currently playing. I'm not sure
				//whether it's possible to change playlist items while remaining paused.
				int usec = (int)req->variables->usec;
				status->time = time(0) * 1000000 - usec;
			}
			string block = dirname(uri);
			string fn = req->variables->name;
			//If we don't have a playlist entry name, use the filename instead.
			if (!fn || fn == "") fn = basename(uri);
			else catch {fn = utf8_to_string(fn);}; //Ditto - UTF-8 with Latin-1 fallback
			//Translate the block names via a per-channel mapping.
			array blocks = channel->config->vlcblocks || ({ });
			string blockdesc;
			foreach (blocks, [string regex, string desc]) {
				array match = Regexp.PCRE(regex, Regexp.PCRE.OPTION.ANCHORED)->split2(block);
				if (!match) continue;
				//Undocumented feature: The description can use regex replacement
				//markers "\1" etc to incorporate matched substrings from the regex.
				blockdesc = replace(desc, mkmapping("\\" + enumerate(sizeof(match))[*], match));
				break;
			}
			if (!blockdesc) {
				blockdesc = "";
				if (!status->unknowns || !has_value(status->unknowns, block)) {
					status->unknowns += ({block});
					//werror("New unknowns: %O\n", status->unknowns);
					send_updates_all("blocks" + channel->name);
				}
			}
			//TODO: Allow filename cleanup to be customized?
			array tails = ({".wav", ".mp3", ".ogg"});
			foreach (tails, string tail) if (has_suffix(fn, tail)) fn = fn[..<sizeof(tail)];
			string desc = fn; if (blockdesc != "") desc = blockdesc + " - " + desc;
			if (desc != status->current) {
				//Add the previous track to the recent ones (if it isn't there already)
				//Note that the current track is NOT in the recents.
				if (!status->recent) status->recent = ({ });
				if (status->current && !has_value(status->recent, status->current))
					status->recent = (status->recent + ({status->current}))[<9..];
				status->current = desc; status->curtrack = fn;
				status->curblock = block; status->curblockdesc = blockdesc;
				status->curnamehash = ""; //Set by the Karaoke engine if needed
				send = 1;
				//write("Changed desc, will report; playing is %O\n%O\n", status->playing, desc);
			}
			//else write("Unchanged desc, no report:\n%O\n", desc);
		}
		if (string s = req->variables->status) {
			int playing = s == "playing";
			send += playing != status->playing;
			status->playing = playing;
			if (req->variables->usec) {
				//The time value sent to the client has two quite different
				//interpretations. If playing is true, this is the time_t when
				//the track "notionally started"; if playing is false, this is
				//the progress through the track. Either way, is in microseconds.
				int usec = (int)req->variables->usec;
				if (playing) status->time = time(0) * 1000000 - usec;
				else status->time = usec;
				//If we start pushing timestamp updates periodically, this might
				//need to set send=1 here, to get those out to the clients.
			}
		}
		if (send) sendstatus(channel); //If multiple changes, only send once
		return (["data": "Okay, fine\n", "type": "text/plain"]);
	}
	if (string which = req->variables->raw) {
		string hash = req->variables->hash;
		if (hash != status->curnamehash) return 0;
		if (which == "webvtt" && status->webvttdata) return (["data": status->webvttdata, "type": "text/vtt"]);
		if (which == "audio") {
			//The Karaoke engine may or may not have provided audio data. If it hasn't,
			//and it is still connected, ask for it (and make the client wait).
			if (status->audiodata) return (["data": status->audiodata, "type": status->audiotype]);
			array engines = websocket_groups[channel->config->vlcauthtoken + channel->name] || ({ });
			if (!sizeof(engines)) return 0; //No karaoke engine connected? No audio available.
			Concurrent.Promise p = Concurrent.Promise();
			if (arrayp(status->audiodata)) status->audiodata += ({p});
			else {
				status->audiodata = ({p});
				//Not using send_updates_all etc because we don't want cmd: "update"
				string text = Standards.JSON.encode((["cmd": "requestaudio", "uri": status->cururi, "hash": hash]), 4);
				foreach (engines, object sock)
					if (sock && sock->state == 1) sock->send_text(text);
			}
			return p->future();
		}
		return 0;
	}
	string chatnotif = "[Enable in-chat notifications](vlc?makespecial)";
	if (G->G->echocommands["!musictrack" + req->misc->channel->name]) {
		//TODO: Show a summary of how it'll look, somehow
		chatnotif = "In-chat notifications active. [Configure details](specials)";
	}
	return render(req, ([
		"vars": (["ws_group": "blocks" * req->misc->is_mod]),
		"showrecents": req->misc->is_mod ? "" : "open=1",
		"save_or_login": replace(MODCONFIG, "<chatnotif>", chatnotif),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "blocks";}
mapping get_chan_state(object channel, string grp, string|void id) {
	if (grp == "blocks" && id) {
		foreach (channel->config->vlcblocks || ({ }), array b)
			if (b[0] == id) return (["id": id, "desc": b[1]]);
		return (["id": id, "desc": ""]);
	}
	mapping status = vlc_status[channel->name];
	if (!status) return (["playing": 0, "current": "", "recent": ({ })]);
	mapping ret = ([
		"playing": status->playing, "current": status->current,
		"recent": status->recent || ({ }), "curnamehash": status->curnamehash,
		"time_usec": status->time,
	]);
	if (grp == "blocks") {
		ret->items = map(channel->config->vlcblocks || ({ }),
			lambda(array b) {return (["id": b[0], "desc": b[1]]);});
		if (status->unknowns) ret->items += (["id": status->unknowns[*], "desc": ""]);
	}
	//When authenticated as the broadcaster's computer (not the broadcaster's Twitch user),
	//include file name information.
	if (grp == channel->config->vlcauthtoken) ret->filename = status->cururi;
	return ret;
}

void websocket_cmd_authreset(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "blocks") return; //Not mod view? No edits.
	channel->config->vlcauthtoken = 0;
	auth_token(channel);
}

void websocket_cmd_karaoke(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != channel->config->vlcauthtoken) return; //Available only to the VLC authenticated computer
	mapping status = vlc_status[channel->name];
	if (!status) return;
	status->curnamehash = msg->namehash; //This will be derived from the full file name, but not reversibly.
	if (arrayp(status->audiodata)) status->audiodata->success((["error": 404]));
	status->audiodata = msg->audiodata; //Might be null
	status->audiotype = msg->audiotype;
	status->webvttdata = msg->webvttdata;
	send_updates_all(channel->name);
	send_updates_all("blocks" + channel->name);
}

void websocket_cmd_provideaudio(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != channel->config->vlcauthtoken) return; //Available only to the VLC authenticated computer
	mapping status = vlc_status[channel->name];
	if (!status) return;
	if (status->curnamehash != msg->namehash) return; //We've moved on, probably.
	if (arrayp(status->audiodata)) status->audiodata->success((["data": msg->audiodata, "type": status->audiotype]));
	status->audiodata = msg->audiodata;
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "blocks") return; //Not mod view? No edits.
	//Match based on the provided ID to recognize overwrites.
	foreach (channel->config->vlcblocks || ({ }); int i; array b) if (b[0] == msg->id) {
		if (msg->desc == "") {
			//Delete.
			channel->config->vlcblocks = channel->config->vlcblocks[..i-1] + channel->config->vlcblocks[i+1..];
		}
		else {
			//Update. It's perfectly valid to update the path - for instance,
			//adjusting a regex - and it should naturally overwrite. But if not,
			//we can do a narrow update; no other things will change.
			b[1] = msg->desc;
			if (msg->path == msg->id) {
				persist_config->save();
				update_one("blocks" + channel->name, msg->id);
				return;
			}
			b[0] = msg->path;
		}
		msg->desc = "";
		break;
	}
	if (msg->desc != "") channel->config->vlcblocks += ({({msg->path, msg->desc})});
	persist_config->save();
	//It's entirely possible that this will match some of the unknowns. If so, clear 'em out.
	mapping status = vlc_status[channel->name];
	if (status->?unknowns) {
		object re = Regexp.PCRE(msg->path, Regexp.PCRE.OPTION.ANCHORED);
		status->unknowns = filter(status->unknowns) {return !re->split2(__ARGS__[0]);};
	}
	send_updates_all("blocks" + channel->name);
}

@hook_channel_offline: int disconnected(string channel) {
	mapping status = vlc_status["#" + channel];
	if (!status) return 0;
	status->playing = 0;
	status->recent = ({ });
}

protected void create(string name) {::create(name);}
