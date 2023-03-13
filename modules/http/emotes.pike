inherit http_endpoint;

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
		int id = (int)req->variables->broadcaster;
		//If you pass ?broadcaster=49497888 this will show for that user ID. Otherwise, look up the name and get the ID.
		if ((string)id != req->variables->broadcaster) id = yield(get_user_id(req->variables->broadcaster));
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
			"emotes": "img", "title": "Channel emotes: " + yield(get_user_info(id))->display_name,
			"text": sprintf("%{\n## %s\n%{%s %}\n%}", emotesets),
		]));
	}
	mapping bot_emote_list = ([]);
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
			set += ({sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0) ", em->code, em->id)});
		}
		set = sort(set) * "";
		if (setid == "0") chan = "Global emotes";
		emote_raw[!highlight[chan]][chan] += emotes;
		if (is_bot)
		{
			//This is all broken thanks to the Kraken shutdown anyway, so just disable it.
			//As of 20221118, the autoform doesn't exist. If functionality like this is
			//needed, put it through a websocket.
			/*if (req->request_type == "POST")
			{
				if (!req->variables[chan]) m_delete(highlight, chan);
				else if (req->variables[chan] && !highlight[chan]) highlight[chan] = time();
				persist_config->save();
				//Fall through using the *new* highlight status
			}*/
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
	if (is_bot) replacements->save = "<input type=submit value=\"Update permanents\">";
	return render_template("emotes.md", replacements);
}
