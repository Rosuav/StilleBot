inherit http_endpoint;

/*
TODO: If logged in as a mod, provide a link usable in OBS. Have an auth token in the
fragment; JS can fetch that and provide it during a WebSocket handshake.
- Tie in with "Retain" disposition per TODO?
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
			array stillunknown = ({ });
			foreach (status->unknowns, string unk)
				if (!re->split2(unk)) stillunknown += ({unk});
			status->unknowns = stillunknown;
		}
		return json_resp(channel);
	}
	mapping status = G->G->vlc_status[channel->name];
	if (req->variables->auth && req->variables->auth == channel->config->vlcauthtoken) {
		//It could be a valid VLC signal.
		if (!status) status = G->G->vlc_status[channel->name] = ([]);
		req->variables->auth = "(correct)"; werror("Got VLC notification: %O\n", req->variables);
		if (req->variables->shutdown) werror("VLC link shutdown\n");
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
			else if (blockdesc != "") blockdesc += " - ";
			//TODO: Allow filename cleanup to be customized?
			array tails = ({".wav", ".mp3", ".ogg"});
			foreach (tails, string tail) if (has_suffix(fn, tail)) fn = fn[..<sizeof(tail)];
			string track = blockdesc + fn;
			if (track != status->current) {
				//Add the previous track to the recent ones (if it isn't there already)
				//Note that the current track is NOT in the recents.
				if (!status->recent) status->recent = ({ });
				if (!has_value(status->recent, status->current))
					status->recent = (status->recent + ({status->current}))[<9..];
				channel->trigger_special("!musictrack", (["user": "VLC"]), ([
					"{track}": track,
				]));
				status->current = track;
			}
		}
		if (string s = req->variables->status)
			status->playing = s == "playing"; //TODO: What happens if the extension is added while we're playing already?
		return (["data": "Okay, fine\n", "type": "text/plain"]);
	}
	if (!status) status = ([]); //but don't save it back, which we would if we're changing stuff
	return render_template("vlc.md", ([
		"modlinks": req->misc->is_mod ?
			"* TODO: OBS link for embedding playback status (using variable substitution??)\n"
			"* [Configure music categories/blocks](vlc?blocks)\n"
			"* [Download Lua script](vlc?lua) - put it into .local/share/vlc/lua/extensions\n"
			"* [Reset credentials](vlc?authreset) - will deauthenticate any previously-downloaded Lua script\n"
			: "",
		"nowplaying": status->playing ? "Now playing: " + status->current : "",
		"recent": arrayp(status->recent) && sizeof(status->recent) ?
			sprintf("Recently played:\n%{* %s\n%}\n{:#recent}", status->recent)
			: "",
	]));
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
