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

//Assign categories to some of the limited-time-unlockable emotes (only if they're kept permanently).
//The actual emote set IDs change, so we detect them by looking for one of the emotes.
constant limited_time_emotes = ([
	"PrideBalloons": "Pride", "PrideWorld": "Pride",
	"HypeBigfoot1": "Hype Train (a)", "HypeChest": "Hype Train (b)", "HypeSwipe": "Hype Train (c)",
	"HahaCat": "Hahahalidays", "RPGPhatLoot": "RPG", "LuvHearts": "Streamer Luv",
	"HyperCrown": "Hyper", "KPOPcheer": "KPOP",
]);

continue Concurrent.Future|mapping fetch_emotes()
{
	if (!G->G->bot_emote_list || G->G->bot_emote_list->fetchtime < time() - 600)
	{
		mapping cfg = persist_config["ircsettings"];
		if (!cfg) return Concurrent.reject("Oops, shouldn't happen");
		if (!cfg->nick || cfg->nick == "") return Concurrent.reject("Oops, shouldn't happen");
		sscanf(cfg["pass"] || "", "oauth:%s", string pass);
		write("Fetching emote list\n");
		mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			0, (["username": cfg->nick, "authtype": "OAuth"])));
		info->fetchtime = time();
		G->G->bot_emote_list = info;
	}
	//TODO: Always update if the sets have changed
	if (!G->G->emote_set_mapping) {
		//NOTE: This fetches only the sets that the bot is able to use. This is
		//a LOT faster than fetching them all (which could take up to 90 secs),
		//but if more sets are added - eg a gift sub is dropped on the bot - then
		//this list becomes outdated :(
		//NOTE: Formerly this used curl due to an unknown failure. If weird stuff
		//happens, go back to 9da66622 and consider reversion.
		write("Fetching emote set info...\n");
		string sets = indices(G->G->bot_emote_list->emoticon_sets) * ",";
		object result = yield(Protocols.HTTP.Promise.get_url("https://api.twitchemotes.com/api/v4/sets?id=" + sets)
			->thencatch() {return __ARGS__[0];}); //Send failures through as results, not exceptions
		if (result->status != 200) {
			write("NOT FETCHED: %O %O\n", result->status, result->status_description);
			G->G->emote_set_mapping = ([]);
			G->G->emote_code_to_markdown = ([]);
			return G->G->bot_emote_list;
		}
		write("Emote set info fetched.\n");
		mapping info = (["fetchtime": time(), "sets": sets]);
		foreach (Standards.JSON.decode(result->get()), mapping setinfo)
			info[setinfo->set_id] = setinfo;
		G->G->emote_set_mapping = info;
		mapping emotes = ([]);
		//What if there's a collision? Should we prioritize?
		foreach (G->G->bot_emote_list->emoticon_sets;; array set) foreach (set, mapping em)
			emotes[em->code] = sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0)", em->code, em->id);
		G->G->emote_code_to_markdown = emotes;
	}
	return G->G->bot_emote_list;
}

continue mapping(string:mixed)|Concurrent.Future|int http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->broadcaster) {
		//Show emotes for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		array emotes = yield(twitch_api_request("https://api.twitch.tv/helix/chat/emotes?broadcaster_id={{USER}}",
			0, (["username": req->variables->broadcaster])))->data;
		mapping sets = ([]);
		foreach (emotes, mapping em) {
			if (em->emote_type == "bitstier") em->emote_set_id = "Bits"; //Hack - we don't get the bits levels anyway, so just group 'em.
			if (!sets[em->emote_set_id]) {
				string desc = "Unknown";
				switch (em->emote_type) {
					case "subscriptions": desc = "Tier " + em->tier[..0]; break;
					case "follower": desc = "Follower"; break;
					case "bitstier": desc = "Bits"; break; //The actual unlock level is missing.
					default: break;
				}
				sets[em->emote_set_id] = ({desc, ({ })});
			}
			sets[em->emote_set_id][1] += ({
				sprintf("<figure>![%s](%s)"
					"<figcaption>%[0]s</figcaption></figure>", em->name, em->images->url_4x)
			});
		}
		array emotesets = values(sets); sort((array(int))indices(sets), emotesets);
		return render_template("checklist.md", ([
			"login_link": "", "emotes": "img", "title": "Channel emotes: " + req->variables->broadcaster,
			"text": sprintf("%{\n## %s\n%{%s %}\n%}", emotesets),
		]));
	}
	if (req->variables->flushcache)
	{
		//Flush the list of the bot's emotes
		if (G->G->bot_emote_list) G->G->bot_emote_list->fetchtime = 0;
		//Also flush the emote set mapping but ONLY if it's at least half an hour old.
		if (G->G->emote_set_mapping->?fetchtime < time() - 1800) G->G->emote_set_mapping = 0;
		return redirect("/emotes");
	}
	mapping bot_emote_list = yield(fetch_emotes());
	mapping highlight = persist_config["permanently_available_emotes"];
	if (!highlight) persist_config["permanently_available_emotes"] = highlight = ([]);
	mapping(string:string) emotesets = ([]);
	array(mapping(string:array(mapping(string:string)))) emote_raw = ({([]), ([])});
	mapping session = G->G->http_sessions[req->cookies->session];
	int is_bot = session->?user->?login == persist_config["ircsettings"]->nick;
	if (!bot_emote_list->emoticon_sets) return render_template("emotes.md", ([
		"emotes": "Unable to fetch emotes from Twitch - check again later",
		"save": "",
	]));
	foreach (bot_emote_list->emoticon_sets; string setid; array emotes)
	{
		mapping setinfo = G->G->emote_set_mapping[setid] //Ideally get info from the API
			|| (["channel_name": "Special unlocks - " + (
				//sprintf("Other (%s)", setid) || //For debugging, uncomment to see the set IDs
				"other" //Otherwise lump them together as "other".
			)]);
		string chan = setinfo->channel_name;
		array|string set = ({ });
		foreach (emotes, mapping em)
		{
			if (string set = limited_time_emotes[em->code])
				//Patch in set names if we recognize an iconic emote from the set
				chan = "Special unlocks - " + set;
			set += ({sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0) ", em->code, em->id)});
		}
		set = sort(set) * "";
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
		else emotesets[chan] = sprintf("\n\n**%s**: %s", G->G->channel_info[chan]->?display_name || chan, set);
	}
	if (req->variables->format == "json") return jsonify(mkmapping(({"permanent", "ephemeral"}), emote_raw), 7);
	array emoteinfo = values(emotesets); sort(indices(emotesets), emoteinfo);
	mapping replacements = (["emotes": emoteinfo * "", "save": ""]);
	if (is_bot)
	{
		replacements->autoform = "<form method=post>";
		replacements->autoslashform = "</form>";
		replacements->save = "<input type=submit value=\"Update permanents\">";
	}
	return render_template("emotes.md", replacements);
}

protected void create(string name)
{
	::create(name);
	mapping cfg = persist_config["ircsettings"];
	if (cfg && cfg->nick && cfg->nick != "" && !G->G->emote_set_mapping)
		fetch_emotes();
}
