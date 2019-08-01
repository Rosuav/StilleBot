inherit http_endpoint;

//If the user is logged in as the bot, emotesets can be added/remove to/from a collection
//of "permanent emotes". These will be highlighted in the emote list. For simplicity, does
//not distinguish tiered emotes - just uses the channel name alone (all available tiers of
//a sub are shown together anyway). It's unlikely that the difference between "permanent T1"
//and "currently T3" will be significant. The channel name is mapped to time() so they can
//be tracked chronologically - we can't do multisets in JSON anyway, so an object will do.

//To access this programmatically: http[s]://SERVERNAME/emotes?format=json
//You'll get back a two-key object "ephemeral" and "permanent", each one mapping channel
//name to array of emotes.

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->flushcache)
	{
		//Flush the list of the bot's emotes
		G->G->bot_emote_list->fetchtime = 0;
		//Also flush the emote set mapping but ONLY if it's at least half an hour old.
		if (G->G->emote_set_mapping->fetchtime < time() - 1800) G->G->emote_set_mapping = 0;
		return redirect("/emotes");
	}
	object ret = Concurrent.resolve(0);
	if (!G->G->bot_emote_list || G->G->bot_emote_list->fetchtime < time() - 600)
	{
		mapping cfg = persist_config["ircsettings"];
		if (!cfg) return (["data": "Oops, shouldn't happen"]);
		if (!cfg->nick || cfg->nick == "") return (["data": "Oops, shouldn't happen"]);
		sscanf(cfg["pass"] || "", "oauth:%s", string pass);
		write("Fetching emote list\n");
		ret = ret->then(lambda() {return get_user_id(cfg->nick);})
		->then(lambda(int id) {
			return Protocols.HTTP.Promise.get_url("https://api.twitch.tv/kraken/users/" + id + "/emotes",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "OAuth " + pass,
				"Accept": "application/vnd.twitchtv.v5+json",
				"Client-ID": cfg->clientid,
			])])));
		})->then(lambda(Protocols.HTTP.Promise.Result res) {
			mapping info = Standards.JSON.decode(res->get());
			info->fetchtime = time();
			G->G->bot_emote_list = info;
		});
	}
	if (!G->G->emote_set_mapping) ret = ret->then(lambda()
	{
		//For some reason, Pike's inbuilt HTTPS client refuses to download this.
		//I'm not sure why. Possibly a cert issue, but I don't know if I can
		//easily just disable cert checking to test that.
		//So we cheat: we call on someone else. TODO: Handle absence of curl by
		//trying python3, python2, wget, or anything else.
		//string data = Protocols.HTTP.get_url_data("https://twitchemotes.com/api_cache/v3/sets.json");
		//NOTE: This is over a hundred megabytes of data. We're forcing the client
		//to wait while we fetch that. Not good. Fortunately it caches easily.
		//Since this is all asynchronous, the rest of the bot is still functional,
		//but the requestor will have to wait a good while.
		write("Fetching emote set info...\n");
		Stdio.File pipe = Stdio.File();
		object promise = Concurrent.Promise();
		object proc = Process.create_process(({"curl", "https://twitchemotes.com/api_cache/v3/sets.json"}),
			(["stdout": pipe->pipe()]));
		array(string) pieces = ({ });
		pipe->set_read_callback(lambda(mixed _, string data) {pieces += ({data});});
		pipe->set_close_callback(lambda() {
			write("Emote set info fetched. (Sorry for the long wait.)\n");
			mapping info = Standards.JSON.decode(pieces * "");
			info->fetchtime = time();
			G->G->emote_set_mapping = info;
			promise->success(0);
		});
		return promise;
	});
	return ret->then(lambda() {
		mapping highlight = persist_config["permanently_available_emotes"];
		if (!highlight) persist_config["permanently_available_emotes"] = highlight = ([]);
		mapping(string:string) emotesets = ([]);
		array(mapping(string:array(mapping(string:string)))) emote_raw = ({([]), ([])});
		mapping session = G->G->http_sessions[req->cookies->session];
		int is_bot = session?->user?->login == persist_config["ircsettings"]->nick;
		foreach (G->G->bot_emote_list->emoticon_sets; string setid; array emotes)
		{
			string set = "";
			foreach (emotes, mapping em)
				set += sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0) ", em->code, em->id);
			mapping setinfo = G->G->emote_set_mapping[setid] || (["channel_name": "Special unlocks"]);
			string chan = setinfo->channel_name;
			if (setid == "0") chan = "Global emotes";
			emote_raw[!highlight[chan]][chan] += emotes;
			if (is_bot)
			{
				if (req->request_type == "POST")
				{
					if (!req->variables[chan]) m_delete(highlight, chan);
					else if (req->variables[chan] && !highlight[chan]) highlight[chan] = time();
					persist_config->save();
					//Fall through using the *new* highlight status
				}
				emotesets[chan + "-Y"] = sprintf("<br><label><input type=checkbox %s name=\"%s\">Permanent</label>",
					"checked" * !!highlight[chan], chan);
			}
			if (highlight[chan]) emotesets[chan + "-Z"] = "\n{: .highlight}";
			if (setinfo->tier > 1) emotesets[chan + "-T" + setinfo->tier] = sprintf(" T%d: %s", setinfo->tier, set);
			else if (emotesets[chan]) emotesets[chan] += sprintf(" %s", set);
			else emotesets[chan] = sprintf("\n\n**%s**: %s", G->G->channel_info[chan]?->display_name || chan, set);
		}
		if (req->variables->format == "json") return ([
			"data": Standards.JSON.encode(mkmapping(({"permanent", "ephemeral"}), emote_raw), 7),
			"type": "application/json",
		]);
		array emoteinfo = values(emotesets); sort(indices(emotesets), emoteinfo);
		return render_template("emotes.md", ([
			"backlink": "",
			"emotes": emoteinfo * "",
			"save": is_bot ? "<input type=submit value=\"Update permanents\">" : "",
		]));
	});
}
