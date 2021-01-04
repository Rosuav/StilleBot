inherit http_endpoint;

/*
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

mapping(string:mixed) json_resp(object channel)
{
	mapping status = G->G->vlc_status[channel->name];
	return (["data": Standards.JSON.encode(([
			"blocks": channel->config->vlcblocks,
			"unknowns": status->?unknowns || ({ }),
		])),
		"type": "application/json",
	]);
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
	if (req->misc->is_mod && req->variables->blocks) {
		array blocks = channel->config->vlcblocks || ({ });
		array unknowns = G->G->vlc_status[channel->name]->?unknowns || ({ });
		return render_template("vlc_blocks.md", ([
			"blocks": Standards.JSON.encode(blocks),
			"unknowns": Standards.JSON.encode(unknowns),
		]));
	}
	if (req->misc->is_mod && req->variables->saveblock && req->request_type == "POST") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!mappingp(body) || !body->path || !body->desc) return (["error": 400]);
		//See if we have the exact same input path. If so, overwrite.
		foreach (channel->config->vlcblocks || ({ }); int i; array b) if (b[0] == body->path) {
			if (body->desc == "") {
				//Delete.
				channel->config->vlcblocks = channel->config->vlcblocks[..i-1] + channel->config->vlcblocks[i+1..];
				return json_resp(channel);
			}
			b[1] = body->desc;
			return json_resp(channel);
		}
		channel->config->vlcblocks += ({({body->path, body->desc})});
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
	if (req->variables->auth && req->variables->auth == channel->config->vlcauthtoken) {
		//It could be a valid VLC signal.
		mapping status = G->G->vlc_status[channel->name];
		if (!status) status = G->G->vlc_status[channel->name] = ([]);
		req->variables->auth = "(correct)"; werror("Got VLC notification: %O\n", req->variables);
		if (req->variables->shutdown) werror("VLC link shutdown\n");
		if (string uri = req->variables->now_playing) {
			catch {uri = utf8_to_string(uri);}; //If it's not UTF-8, pretend it's Latin-1
			string block = dirname(uri);
			string fn = basename(uri);
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
				blockdesc = "Unknown"; //TODO: Allow this to be customized
				if (!status->unknowns || !has_value(status->unknowns, block))
					status->unknowns += ({block});
				werror("New unknowns: %O\n", status->unknowns);
			}
			//TODO: Allow filename cleanup to be customized?
			//TODO: If we get metadata from VLC, use that instead
			array tails = ({".wav", ".mp3", ".ogg"});
			foreach (tails, string tail) if (has_suffix(fn, tail)) fn = fn[..<sizeof(tail)];
			string track = sprintf("%s - %s", blockdesc, fn);
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
	return render_template("vlc.md", ([
		"modlinks": req->misc->is_mod ? "* [Configure music categories/blocks](vlc?blocks)" : "",
	]));
}

protected void create(string name) {::create(name); G->G->vlc_status = ([]);}
