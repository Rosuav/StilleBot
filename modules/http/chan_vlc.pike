inherit http_endpoint;
inherit websocket_handler;

/* TODO: Merge block management into the main page.

This will also make it worth having a standard "Mods, log in" link on that same page.

Use websocket with group "blocks#channelname" to get the blocks and the ability to edit.

This group should get all regular notifications as well as changes to blocks. On the front
end, show everything based on the incoming render message, but on the back end, don't offer
the "blocks" group unless you're a mod.
*/

/* Am getting some duplicated messages, sometimes with "paused" followed by "playing".
Theory: VLC is announcing status of "loading", the Lua script is announcing that as "not
playing", and Pike is interpreting that as "paused". Then when the file finishes loading,
it gets the "playing" status, and pushes the notif through.

Solution #1: If "loading", ignore the status change; but that's supposed to be already
happening. Check what the actual values are, and see if the "4" needs changing.

Solution #2: If we change from playing to paused to playing inside 2s, suppress text. This
would be done in the default command, NOT here in the code.
*/

/*
* Hide recent tracks behind details/summary in mod view
* Hide setup behind details/summary. Have full instructions.
  - Have it start open if no token?
*/

//Create (if necessary) and return the VLC Auth Token
string auth_token(object channel) {
	if (string t = channel->config->vlcauthtoken) return t;
	persist_config->save();
	return channel->config->vlcauthtoken = String.string2hex(random_string(12));
}

mapping(string:mixed) json_resp(object channel)
{
	mapping status = G->G->vlc_status[channel->name];
	return jsonify(([
		"blocks": channel->config->vlcblocks,
		"unknowns": status->?unknowns || ({ }),
	]));
}

void sendstatus(object channel) {
	mapping status = G->G->vlc_status[channel->name] || ([]);
	channel->trigger_special("!musictrack", (["user": "VLC"]), ([
		"{playing}": (string)status->playing,
		"{desc}": status->current || "",
		"{blockpath}": status->curblock || "",
		"{block}": status->curblockdesc || "",
		"{track}": status->curtrack || "",
	]));
	send_updates_all(channel->name);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	object channel = req->misc->channel;
	if (req->misc->is_mod && req->variables->authreset) {
		return render_template("vlc.md", (["modlinks": "* [Confirm auth reset?](vlc?authresetconfirm)"]));
	}
	if (req->misc->is_mod && req->variables->authresetconfirm) {
		channel->config->vlcauthtoken = 0; auth_token(channel);
		return redirect("vlc");
	}
	if (req->misc->is_mod && req->variables->makespecial) {
		//Note that this option isn't made obvious if you already have the command,
		//but we won't stop you from using it if you do so manually. It'll overwrite.
		make_echocommand("!musictrack" + req->misc->channel->name, ({
			(["dest": "/set", "message": "{playing}", "target": "vlcplaying"]),
			(["dest": "/set", "message": "{desc}", "target": "vlccurtrack"]),
			(["delay": 2, "message": ([
				"conditional": "string", "expr1": "$vlcplaying$", "expr2": "1",
				"message": "SingsNote Now playing: {track} ({block}) SingsNote",
				"otherwise": ""
			])]),
		}));
		return redirect("vlc");
	}
	if (req->misc->is_mod && req->variables->lua) {
		mapping cfg = persist_config["ircsettings"];
		mapping resp = render_template("vlcstillebot.lua", ([
			"url": cfg->http_address + req->not_query,
			"auth": auth_token(channel),
		]));
		resp->type = "application/x-lua";
		resp->extra_heads = (["Content-disposition": "attachment; filename=vlcstillebot.lua"]);
		return resp;
	}
	if (req->misc->is_mod && req->variables->blocks) {
		array blocks = channel->config->vlcblocks || ({ });
		array unknowns = G->G->vlc_status[channel->name]->?unknowns || ({ });
		return render_template("vlc_blocks.md", (["vars": ([
			"blocks": blocks,
			"unknowns": unknowns,
		])]));
	}
	if (req->misc->is_mod && req->variables->saveblock && req->request_type == "POST") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!mappingp(body) || !body->path || !body->desc) return (["error": 400]);
		//See if we have the exact same input path. If so, overwrite.
		foreach (channel->config->vlcblocks || ({ }); int i; array b) if (b[0] == body->path) {
			if (body->desc == "") {
				//Delete.
				channel->config->vlcblocks = channel->config->vlcblocks[..i-1] + channel->config->vlcblocks[i+1..];
				persist_config->save();
				return json_resp(channel);
			}
			b[1] = body->desc;
			return json_resp(channel);
		}
		if (body->desc != "") channel->config->vlcblocks += ({({body->path, body->desc})});
		persist_config->save();
		//It's entirely possible that this will match some of the unknowns. If so, clear 'em out.
		mapping status = G->G->vlc_status[channel->name];
		if (status->?unknowns) {
			object re = Regexp.PCRE(body->path, Regexp.PCRE.OPTION.ANCHORED);
			status->unknowns = filter(status->unknowns) {return !re->split2(__ARGS__[0]);};
		}
		return json_resp(channel);
	}
	mapping status = G->G->vlc_status[channel->name];
	if (req->variables->auth && req->variables->auth == channel->config->vlcauthtoken) {
		//It could be a valid VLC signal.
		if (!status) status = G->G->vlc_status[channel->name] = ([]);
		req->variables->auth = "(correct)"; werror("Got VLC notification: %O\n", req->variables);
		if (req->variables->shutdown) {req->variables->status = "shutdown"; werror("VLC link shutdown\n");}
		if (string uri = req->variables->now_playing) {
			catch {uri = utf8_to_string(uri);}; //If it's not UTF-8, pretend it's Latin-1
			string block = dirname(uri);
			string fn = req->variables->name;
			//If we don't have a playlist entry name, use the filename instead.
			if (!fn || fn == "") fn = basename(uri);
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
				if (!status->unknowns || !has_value(status->unknowns, block))
					status->unknowns += ({block});
				werror("New unknowns: %O\n", status->unknowns);
			}
			//TODO: Allow filename cleanup to be customized?
			array tails = ({".wav", ".mp3", ".ogg"});
			foreach (tails, string tail) if (has_suffix(fn, tail)) fn = fn[..<sizeof(tail)];
			string desc = fn; if (blockdesc != "") desc = blockdesc + " - " + desc;
			if (desc != status->current) {
				//Add the previous track to the recent ones (if it isn't there already)
				//Note that the current track is NOT in the recents.
				if (!status->recent) status->recent = ({ });
				if (!has_value(status->recent, status->current))
					status->recent = (status->recent + ({status->current}))[<9..];
				status->current = desc; status->curtrack = fn;
				status->curblock = block; status->curblockdesc = blockdesc;
				if (!req->variables->status) sendstatus(channel); //If there's also a status set, make both changes atomically before invoking the special.
			}
		}
		if (string s = req->variables->status) {
			status->playing = s == "playing";
			sendstatus(channel);
		}
		return (["data": "Okay, fine\n", "type": "text/plain"]);
	}
	if (!status) status = ([]); //but don't save it back, which we would if we're changing stuff
	string chatnotif = "* [Enable in-chat notifications](vlc?makespecial)\n";
	if (G->G->echocommands["!musictrack" + req->misc->channel->name]) {
		//TODO: Show a summary of how it'll look, somehow
		chatnotif = "* In-chat notifications active. [Configure details](specials)";
	}
	return render_template("vlc.md", ([
		"vars": (["ws_type": "chan_vlc", "ws_group": req->misc->channel->name]), //TODO: "blocks" + channelname for mod view
		"modlinks": req->misc->is_mod ?
			"* [Configure music categories/blocks](vlc?blocks)\n"
			"* [Download Lua script](vlc?lua) - put it into .local/share/vlc/lua/extensions (create that dir if needed)\n"
			"* [Reset credentials](vlc?authreset) - will deauthenticate any previously-downloaded Lua script\n"
			+ chatnotif
			: "",
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if (!channel) return "Bad channel";
	conn->is_mod = channel->mods[conn->session->?user->?login];
	if (grp == "blocks" && !conn->is_mod) return "Not logged in";
}

mapping get_state(string group, string|void id) {
	[object channel, string grp] = split_channel(group);
	if (!channel) return 0;
	mapping status = G->G->vlc_status[channel->name];
	if (!status) return (["playing": 0, "current": "", "recent": ({ })]);
	if (grp == "blocks") ; // TODO
	return (["playing": status->playing, "current": status->current, "recent": status->recent || ({ })]);
}

int disconnected(string channel) {
	mapping status = G->G->vlc_status["#" + channel];
	if (!status) return 0;
	status->playing = 0;
	status->recent = ({ });
}

protected void create(string name) {
	::create(name);
	if (!G->G->vlc_status) G->G->vlc_status = ([]);
	register_hook("channel-online", disconnected); //CJA 2021-03-07: Was this supposed to be OFFline?
}
