inherit http_endpoint;

//TODO: If logged in as the bot, allow emotesets to be added/remove to/from a collection
//of "permanent emotes". These will be highlighted in the emote list. For simplicity, do
//not distinguish tiered emotes; just use the channel name alone, and highlight all tiers
//that are currently available. (It's unlikely that the difference between "permanent T1"
//and "currently T3" will be significant.) Map the channel name to time() so they can be
//tracked chronologically - we can't do multisets in JSON anyway, so an object will do.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->flushcache)
	{
		//Flush the list of the bot's emotes
		G->G->bot_emote_list->fetchtime = 0;
		//Also flush the emote set mapping but ONLY if it's at least half an hour old.
		if (G->G->emote_set_mapping->fetchtime < time() - 1800) G->G->emote_set_mapping = 0;
		return redirect("/emotes");
	}
	if (!G->G->bot_emote_list || G->G->bot_emote_list->fetchtime < time() - 600)
	{
		mapping cfg = persist_config["ircsettings"];
		if (!cfg) return (["data": "Oops, shouldn't happen"]);
		if (!cfg->nick || cfg->nick == "") return (["data": "Oops, shouldn't happen"]);
		sscanf(cfg["pass"] || "", "oauth:%s", string pass);
		write("Fetching emote list\n");
		//TODO: Asyncify this
		string data = Protocols.HTTP.get_url_data("https://api.twitch.tv/kraken/users/" + cfg->nick + "/emotes", 0, ([
			"Authorization": "OAuth " + pass,
			"Client-ID": cfg->clientid,
		]));
		mapping info = Standards.JSON.decode(data);
		info->fetchtime = time();
		G->G->bot_emote_list = info;
	}
	if (!G->G->emote_set_mapping)
	{
		//TODO: Asyncify this too
		//For some reason, Pike's inbuilt HTTPS client refuses to download this.
		//I'm not sure why. Possibly a cert issue, but I don't know if I can
		//easily just disable cert checking to test that.
		//So we cheat: we call on someone else. TODO: Handle absence of curl by
		//trying python3, python2, wget, or anything else.
		//string data = Protocols.HTTP.get_url_data("https://twitchemotes.com/api_cache/v3/sets.json");
		//NOTE: This is over a hundred megabytes of data. We're forcing EVERYONE
		//to wait while we fetch that. Not good. Fortunately it caches easily.
		write("Fetching emote set info...\n");
		string data = Process.run(({"curl", "https://twitchemotes.com/api_cache/v3/sets.json"}))->stdout;
		write("Emote set info fetched. (Sorry for the big lag.)\n");
		mapping info = Standards.JSON.decode(data);
		info->fetchtime = time();
		G->G->emote_set_mapping = info;
	}
	mapping highlight = persist_config["permanently_available_emotes"];
	if (!highlight) persist_config["permanently_available_emotes"] = highlight = ([]);
	mapping(string:string) emotesets = ([]);
	foreach (G->G->bot_emote_list->emoticon_sets; string setid; array emotes)
	{
		string set = "";
		foreach (emotes, mapping em)
			set += sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0) ", em->code, em->id);
		mapping setinfo = G->G->emote_set_mapping[setid] || (["channel_name": "Special unlocks"]);
		string chan = setinfo->channel_name;
		if (setid == "0") chan = "Global emotes";
		if (highlight[chan]) emotesets[chan + "-Z"] = "\n{: .highlight}";
		if (setinfo->tier > 1) emotesets[chan + "-T" + setinfo->tier] = sprintf(" T%d: %s", setinfo->tier, set);
		else if (emotesets[chan]) emotesets[chan] += sprintf(" %s", set);
		else emotesets[chan] = sprintf("\n\n**%s**: %s", G->G->channel_info[chan]?->display_name || chan, set);
	}
	array emoteinfo = values(emotesets); sort(indices(emotesets), emoteinfo);
	return render_template("emotes.md", ([
		"channel": "hack", //TODO: Deal with this (we don't want a back link, there's no channel page)
		"emotes": emoteinfo * "",
	]));
}
