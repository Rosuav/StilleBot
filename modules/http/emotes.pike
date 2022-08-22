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
		//Kraken's down.
		/*mapping info = yield(G->G->external_api_lookups->get_user_emotes(cfg->nick));
		info->fetchtime = time();
		G->G->bot_emote_list = info;*/
		G->G->bot_emote_list = ([]);
		G->G->emote_set_mapping = ([]); //TODO: Manually group them?
	}
	//TODO: Always update if the sets have changed
	mapping emotes = G->G->emote_code_to_markdown || ([]);
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
		//What if there's a collision? Should we prioritize?
		foreach (G->G->bot_emote_list->emoticon_sets;; array set) foreach (set, mapping em)
			emotes[em->code] = sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0)", em->code, em->id);
	}
	//Augment (or replace) with any that we've seen that the bot has access to
	foreach (persist_status->path("bot_emotes"); string code; string id) {
		//Note: Uses the v2 URL scheme even if it's v1 - they seem to work
		emotes[code] = sprintf("![%s](%s)", code, emote_url((string)id, 1));
	}
	G->G->emote_code_to_markdown = emotes;
	return G->G->bot_emote_list;
}

continue mapping(string:mixed)|Concurrent.Future|int http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->cheer) {
		//Show cheeremotes, possibly for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/cheermotes?broadcaster_id={{USER}}",
			0, (["username": req->variables->broadcaster || "twitch"])));
		array emotes = info->data; info->data = "<suppressed>";
		array cheeremotes = ({ });
		foreach (emotes, mapping em) {
			array tiers = ({ });
			multiset(string) flags = (<"Unavailable", "Hidden">);
			foreach (em->tiers || ({ }), mapping tier) {
				tiers += ({
					sprintf("<figure>![%s](%s)"
						"<figcaption style=\"color: %s\">%[0]s</figcaption></figure>",
						em->prefix + tier->id,
						tier->images->light->animated["4"],
						tier->color || "black")
				});
				if (tier->can_cheer) flags->Unavailable = 0;
				if (tier->show_in_bits_card) flags->Hidden = 0;
			}
			if (em->is_charitable) flags->Charitable = 1;
			if (em->type == "display_only") flags["Display-only"] = 1;
			if (em->type == "global_third_party") flags["Third-party"] = 1;
			if (em->type == "channel_custom") flags["Channel-unique"] = 1;
			cheeremotes += ({({em->prefix, sizeof(flags) ? "\n#### " + sort(indices(flags)) * ", " : "", tiers})});
		}
		return render_template("checklist.md", ([
			"login_link": "", "emotes": "img", "title": "Cheer emotes: " + (req->variables->broadcaster || "global"),
			"text": sprintf("%{\n## %s%s\n%{%s %}\n%}", cheeremotes),
			//sprintf("<pre>%O</pre>", cheeremotes),
		]));
	}
	if (req->variables->broadcaster) {
		//Show emotes for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		int id = yield(get_user_id(req->variables->broadcaster));
		array emotes = yield(twitch_api_request("https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + id))->data;
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
				//As of 2022, only T1 sub emotes are ever animated, but if that ever changes, we'll be ready!
				if (has_value(em->format, "animated")) desc = "Animated " + desc;
				sets[em->emote_set_id] = ({desc, ({ })});
			}
			sets[em->emote_set_id][1] += ({
				sprintf("<figure>![%s](%s)"
					"<figcaption>%[0]s</figcaption></figure>", em->name,
					replace(em->images->url_4x, "/static/", "/default/")) //Most emotes have the same image for static and default. Anims get a one-frame for static, and the animated for default.
			});
		}
		//Also fetch the badges. They're intrinsically at a different size, but they'll be stretched to the same size.
		//If that's a problem, it'll need to be solved in CSS (probably with a classname on the figure here).
		array badges = yield(twitch_api_request("https://api.twitch.tv/helix/chat/badges?broadcaster_id=" + id))->data;
		foreach (badges, mapping set) {
			mapping cur = ([]);
			if (set->set_id == "subscriber") cur[1999] = cur[2999] = "<br>";
			foreach (set->versions, mapping badge) {
				string desc = badge->id;
				if (set->set_id == "subscriber") {
					int tier = (int)badge->id / 1000;
					int tenure = (int)badge->id % 1000;
					desc = ({"T1", 0, "T2", "T3"})[tier];
					if (tenure) desc += ", " + tenure + " months";
					else desc += ", base";
				}
				cur[(int)badge->id] = sprintf("<figure>![%s](%s)"
						"<figcaption>%[0]s</figcaption></figure>",
						desc, badge->image_url_4x,
				);
			}
			array b = values(cur); sort(indices(cur), b);
			if (set->set_id == "subscriber") sets[1<<29] = ({"Subscriber badges", b});
			if (set->set_id == "bits") sets[1<<30] = ({"Bits badges", b});
		}
		array emotesets = values(sets); sort((array(int))indices(sets), emotesets);
		if (!sizeof(emotesets)) emotesets = ({({"None", ({"No emotes found for this channel. Partnered and affiliated channels have emote slots available; emotes awaiting approval may not show up here."})})});
		return render_template("checklist.md", ([
			"login_link": "<button id=greyscale onclick=\"document.body.classList.toggle('greyscale')\">Toggle Greyscale (value check)</button>",
			"emotes": "img", "title": "Channel emotes: " + req->variables->broadcaster,
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
		spawn_task(fetch_emotes());
}
