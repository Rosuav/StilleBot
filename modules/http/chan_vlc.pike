inherit http_endpoint;

/*
TODO: If logged in as a mod, allow a download of the Lua script, with an embedded URL and
channel authentication token.

TODO: If logged in as a mod, provide a link usable in OBS. Have an auth token in the
fragment; JS can fetch that and provide it during a WebSocket handshake.
- Tie in with "Retain" disposition per TODO?

TODO: If logged in as a mod, allow reset of the channel token (which will invalidate any
Lua script or OBS link).
*/

//Create (if necessary) and return the VLC Auth Token
string auth_token(object channel) {
	if (string t = channel->config->vlcauthtoken) return t;
	persist_config->save();
	return channel->config->vlcauthtoken = String.string2hex(random_string(12));
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	object channel = req->misc->channel;
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
	if (req->variables->auth && req->variables->auth == channel->config->vlcauthtoken) {
		//It could be a valid VLC signal.
		mapping status = G->G->vlc_status[channel->name];
		if (!status) status = G->G->vlc_status[channel->name] = ([]);
		req->variables->auth = "(correct)"; werror("Got VLC notification: %O\n", req->variables);
		if (req->variables->shutdown) werror("VLC link shutdown\n");
		if (string uri = req->variables->now_playing) {
			string block = dirname(uri);
			string fn = basename(uri);
			//TODO: Translate the block names via a per-channel mapping.
			//Possibly have some sscanf patterns eg "StreamingMusic/DarkFantasyStudio/%s/%s"
			//to be described as "DFS: %1" with track name "%2"
			block = ([])[block] || "Unknown";
			array tails = ({".wav", ".mp3", ".ogg"});
			foreach (tails, string tail) if (has_suffix(fn, tail)) fn = fn[..<sizeof(tail)];
			string track = sprintf("%s - %s", block, fn);
			if (channel->config->report_track_changes && track != status->current) {
				//TODO: Allow the format to be customized
				//TODO: Have a configurable delay before the message is sent.
				//(Helps with synchronization a bit.)
				channel->wrap_message((["displayname": ""]),
					"Now playing: " + track,
				);
			}
			status->current = track;
		}
		if (string s = req->variables->status)
			status->playing = s == "playing";
		return (["data": "Okay, fine\n", "type": "text/plain"]);
	}
	return render_template("vlc.md", ([]));
}

protected void create(string name) {::create(name); G->G->vlc_status = ([]);}
