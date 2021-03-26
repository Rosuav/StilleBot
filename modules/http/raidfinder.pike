inherit http_endpoint;
/* Raid target finder
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - There's not going to be any easy UI for it, but it'd be great to have a "raided my friend"
    feature, where we can see any time that X raided Y where Y is one of my friends... hard.

TODO: Put a real space between tags so highlighting works correctly.
-- The browser seems to be ditching it for me. Not sure why, or how to stop it.
*/

void update_tags(array alltags) {
	if (!alltags) return; //Shouldn't happen
	mapping tags = G->G->all_stream_tags;
	foreach (alltags, mapping tag) tags[tag->tag_id] = ([
		"id": tag->tag_id,
		"name": tag->localization_names["en-us"],
		"desc": tag->localization_descriptions["en-us"],
		"auto": tag->is_auto,
	]);
}

constant MAX_PREF = 3, MIN_PREF = -3;
constant PREFERENCE_MAGIC_SCORES = ({
	0, //Must have 0 for score 0
	50, 250, 1000, //Positive ratings
	0, 0, 0, 0, //Shims, just in case (shouldn't be necessary)
	-1000, -250, -50, //Negative ratings
});

//Fracture a big array into a set of smaller ones and await them all
//Should get_helix_paginated handle this automatically??
Concurrent.Future fracture(array stuff, int max, function cb) {
	return Concurrent.all(cb((stuff / (float)max)[*]))->then() {return __ARGS__[0] * ({ });};
}

multiset(string) creative_names = (<"Art", "Science & Technology", "Food & Drink", "Music", "Makers & Crafting", "Beauty & Body Art">);
multiset(int) creatives = (<>);

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Try to find all creative categories and get their IDs. Is there a better way to do this?
	if (sizeof(creatives) < sizeof(creative_names)) {
		//If any aren't found, we'll scan this list repeatedly every time a page is loaded.
		foreach (G->G->category_names; int id; string name)
			if (creative_names[name]) creatives[id] = 1;
	}
	if (req->request_type == "POST")
	{
		//Update notes
		if (mapping resp = ensure_login(req, "user_read")) return (["error": 401]);
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body) || !intp(body->id)) return (["error": 400]);
		string newnotes = body->notes || "";
		mapping notes = persist_status->path("raidnotes", (string)req->misc->session->user->id);
		if (body->id == 0)
		{
			//Special case: List of highlight channels.
			//Channel names are separated by space or newline or comma or whatever
			array(string) channels = replace(newnotes, ",;\n"/"", " ") / " " - ({""});
			//Trim URLs down to just the channel name
			foreach (channels; int i; string c) sscanf(c, "http%*[s]://twitch.tv/%s%*[?/]", channels[i]);
			array users = yield(get_users_info(channels, "login")); //TODO: If this throws "user not found", report it nicely
			notes->highlight = (array(string))users->id * "\n";
			persist_status->save();
			return jsonify(([
				"highlights": users->login * "\n",
				"highlightids": users->id,
			]), 7);
		}
		if (body->id == -1) { //Should the front end use the same keywords??
			//Update tag preferences. Note that this does NOT fully replace
			//existing tag prefs; it changes only those which are listed.
			//Note also that tag prefs, unlike other raid notes, are stored
			//as a mapping.
			if (!notes->tags) notes->tags = ([]);
			foreach (newnotes / "\n", string line) 
				if (sscanf(line, "%s %d", string id, int pref) == 2) {
					if (!pref || pref > MAX_PREF || pref < MIN_PREF) m_delete(notes->tags, id);
					else notes->tags[id] = pref;
				}
			persist_status->save();
			return jsonify((["ok": 1, "prefs": notes->tags]));
		}
		if (newnotes == "") m_delete(notes, (string)body->id);
		else notes[(string)body->id] = newnotes;
		persist_status->save();
		return (["error": 204]);
	}
	mapping logged_in = req->misc->session && req->misc->session->user;
	int userid = 0;
	if (string chan = req->variables["for"])
	{
		//When fetching raid info on behalf of another streamer, you see your own follow
		//list, but that streamer's raid history. It's good for making recommendations.
		//It's NOT the same as the streamer checking the raid finder.
		//write("On behalf of %O\n", chan);
		if (chan == "online") //Hack: "for=online" will look at which bot-tracked channels are online.
		{
			array online = indices(G->G->stream_online_since);
			if (!sizeof(online)) return (["data": "Nobody's online that I can see!", "type": "text/plain"]);
			if (sizeof(online) == 1) return redirect("/raidfinder?for=" + online[0]); //Send you straight there if only one
			return (["data": sprintf("<ul>%{<li><a href=\"/raidfinder?for=%s\">%<s</a></li>%}</ul>", sort(online)),
				"type": "text/html"]);
		}
		userid = yield(get_user_id(chan));
	}
	else if (logged_in) userid = (int)logged_in->id; //Raidfind for self if logged in.
	//TODO: Based on the for= or the logged in user, determine whether raids are tracked.
	mapping raids = ([]);
	array follows_kraken, follows_helix;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for=
	//annotation. For notes attached to a channel, that channel's ID is
	//used; other forms of notes are attached to specific keywords. In a
	//previous iteration of this, notes ID 0 was used for "highlight".
	mapping notes = persist_status->path("raidnotes")[(string)logged_in?->id] || ([]);
	array highlightids = ({ });
	if (notes["0"]) notes->highlight = m_delete(notes, "0"); //Migrate
	if (notes->highlight) highlightids = (array(int))(notes->highlight / "\n");
	string highlights;
	if (req->variables->allfollows)
	{
		//Show everyone that you follow (not just those who are live), in an
		//abbreviated form, mainly for checking notes.
		if (mapping resp = ensure_login(req, "user_read")) return resp;
		array f = yield(get_helix_paginated("https://api.twitch.tv/helix/users/follows",
				(["from_id": (string)req->misc->session->user->id])));
		//TODO: Make a cleaner way to fragment requests - we're gonna need it.
		array(array(string)) blocks = f->to_id / 100.0;
		follows_helix = yield(Concurrent.all(twitch_api_request(("https://api.twitch.tv/helix/users?first=100" + sprintf("%{&id=%s%}", blocks[*])[*])[*])))->data * ({ });
		array users = yield(get_users_info(highlightids));
		highlights = users->login * "\n";
		foreach (follows_helix; int idx; mapping strm) {
			if (string n = notes[strm->id]) strm->notes = n;
			if (has_value(highlightids, (int)strm->id)) strm->highlight = 1;
			strm->order = idx; //Order they were followed. Effectively the same as array order since we don't get actual data.
			//Make some info available in the same way that it is for the main follow list.
			//This allows the front end to access it identically for convenience.
			strm->user_name = strm->display_name;
		}
		return render_template("raidfinder.md", ([
			"vars": (["follows": follows_helix, "your_stream": 0, "highlights": highlights, "all_raids": ({}), "mode": "allfollows"]),
			"sortorders": ({"Channel Creation", "Follow Date", "Name"}) * "\n* ",
		]));
	}
	if (!G->G->all_stream_tags) {
		array tags = yield(get_helix_paginated("https://api.twitch.tv/helix/tags/streams"));
		//This will normally catch every tag, but in the event that we have
		//an incomplete cached set of tags (eg if Twitch creates new tags),
		//the check below will notice this as soon as we spot a stream using
		//the new tag.
		G->G->all_stream_tags = ([]);
		update_tags(tags);
	}
	string login, disp;
	if (logged_in && (int)logged_in->id == userid) {login = logged_in->login; disp = logged_in->display_name;}
	else if (mapping user = userid && G->G->user_info[userid])
	{
		login = user->login || user->name; //helix || kraken
		disp = user->display_name;
	}
	if (login) foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n", string raid)
	{
		sscanf(raid, "[%d-%d-%d %*d:%*d:%*d] %s => %s", int y, int m, int d, string from, string to);
		if (!to) continue;
		if (y >= 2021 && m > 3) break; //Ignore newer entries and rely on the proper format (when should the cutoff be?)
		if (from == login) raids[lower_case(to)] += ({sprintf(">%d-%02d-%02d %s raided %s", y, m, d, from, to)});
		if (to == disp) raids[from] += ({sprintf("<%d-%02d-%02d %s raided %s", y, m, d, from, to)});
	}
	array users = yield(get_users_info(highlightids));
	highlights = users->login * "\n";
	string title = "Followed streams";
	//Category search - show all streams in the categories you follow
	if (req->variables->raiders || req->variables->categories) {
		mapping args = ([]);
		switch (req->variables->categories) {
			case 0: { //Raiders mode (categories omitted but "?raiders" specified). Particularly useful with a for= search.
				//List everyone who's raided you, including their timestamps
				//Assume that the last entry in each array is the latest.
				//The result is that raiders will contain one entry for each
				//unique user ID that has ever been raided, and raidtimes will
				//have the corresponding timestamps.
				array raiders = ({ }), raidtimes = ({ });
				foreach (persist_status->path("raids"); string id; mapping raids) {
					if (id == (string)userid)
						foreach (raids; string otherid; array raids) {
							foreach (reverse(raids), mapping r)
								if (!r->outgoing) {raiders += ({otherid}); raidtimes += ({r->timestamp}); break;}
						}
					else foreach (reverse(raids[(string)userid] || ({ })), mapping r)
						if (r->outgoing) {raiders += ({(string)userid}); raidtimes += ({r->timestamp}); break;}
				}
				sort(raidtimes, raiders);
				args->user_id = raiders[<99..]; //Is it worth trying to support more than 100 raiders? Would need to paginate.
				break;
			}
			default: { //For ?categories=Art,Food%20%26%20Drink - explicit categories
				array cats = yield(get_helix_paginated("https://api.twitch.tv/helix/games", (["name": req->variables->categories / ","])));
				if (sizeof(cats)) {
					args->game_id = (array(string))cats->id;
					title = cats->name * ", " + " streams";
					break;
				}
				//Else fall through. Any sort of junk category name, treat it as if it's "?categories"
			}
			case "": case "categories": { //For ?categories and ?categories= modes, show those you follow
				if (mapping resp = ensure_login(req, "user_read")) return resp;
				mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/users/" + req->misc->session->user->id + "/follows/games"));
				args->game_id = (array(string))info->follows->game->_id;
				title = "Followed categories";
				break;
			}
		}
		[array streams, mapping self] = yield(Concurrent.all(
			get_helix_paginated("https://api.twitch.tv/helix/streams", args),
			twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + userid),
		));
		array(string) ids = streams->user_id + ({(string)userid});
		//Map channel list to Kraken so we get both sets of info
		follows_helix = streams + self->data;
		//If you follow a large number of categories, or a single large category,
		//there could be rather a lot of IDs. Fetch in blocks.
		follows_kraken = ({ }); //Not currently using any Kraken info (yay!), so skip fetching it.
		/*follows_kraken = yield(fracture(ids, 25) {
			return twitch_api_request("https://api.twitch.tv/kraken/streams/?channel=" + __ARGS__[0] * ",")
				->then() {return __ARGS__[0]->streams;};
		});*/
		users = yield(fracture(ids, 100) {return get_helix_paginated("https://api.twitch.tv/helix/users", (["id": __ARGS__[0]]));});
	}
	else {
		if (mapping resp = ensure_login(req, "user_read")) return resp;
		mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/streams/followed?limit=100",
			(["Authorization": "OAuth " + req->misc->session->token])));
		array(int) channels = info->streams->channel->_id;
		channels += ({userid});
		write("Fetching %d streams...\n", sizeof(channels));
		//Map channel list to Helix so we get both sets of info
		follows_kraken = info->streams;
		[follows_helix, users] = yield(Concurrent.all(
			get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": (array(string))channels])),
			//The ONLY thing we need /helix/users for is broadcaster_type, which - for
			//reasons unknown to me - is always blank in the main stream info.
			get_helix_paginated("https://api.twitch.tv/helix/users", (["id": (array(string))channels])),
		));
	}
	//write("Kraken: %O\nHelix: %O\nUsers: %O\n", follows_kraken[..3], follows_helix[..3], users[..3]);
	mapping your_stream;
	multiset need_tags = (<>);
	foreach (follows_helix, mapping strm)
	{
		foreach (strm->tag_ids || ({ }), string tag)
			if (!G->G->all_stream_tags[tag]) need_tags[tag] = 1;
		if ((int)strm->user_id == userid) your_stream = strm;
	}
	if (sizeof(need_tags)) {
		//Normally we'll have all the tags from the check up above, but in case, we catch more here.
		write("Fetching %d tags...\n", sizeof(need_tags));
		update_tags(yield(get_helix_paginated("https://api.twitch.tv/helix/tags/streams", (["tag_id": (array)need_tags]))));
	}
	mapping(int:mapping(string:mixed)) extra_info = ([]);
	foreach (follows_kraken, mapping strm) //NOTE: As of 2021-03-13, this isn't actually needed. Keeping in case I lift more info.
		extra_info[strm->channel->_id] = ([
			"profile_image_url": strm->channel->logo,
			"url": strm->channel->url,
			//strm->video_height and strm->average_fps might be of interest
		]);
	foreach (users, mapping user)
		extra_info[(int)user->id] = ([
			"broadcaster_type": user->broadcaster_type,
			"profile_image_url": user->profile_image_url,
		]) | (extra_info[(int)user->id] || ([]));
	//Okay! Preliminaries done. Let's look through the Helix-provided info and
	//build up a final result.
	mapping tag_prefs = notes->tags || ([]);
	foreach (follows_helix; int i; mapping strm)
	{
		mapping(string:int) recommend = ([]);
		array tags = ({ });
		foreach (strm->tag_ids || ({ }), string tagid) {
			if (mapping tag = G->G->all_stream_tags[tagid]) tags += ({tag});
			if (int pref = tag_prefs[tagid]) recommend["Tag prefs"] += PREFERENCE_MAGIC_SCORES[pref];
		}
		strm->tags = tags;
		strm->category = G->G->category_names[strm->game_id];
		strm->raids = raids[strm->user_login] || ({ });
		int otheruid = (int)strm->user_id;
		if (otheruid == userid) {follows_helix[i] = 0; continue;} //Exclude self. There's no easy way to know if you should have shown up, so just always exclude.
		//TODO: Configurable hard tag requirements
		//if (recommend["Tag prefs"] <= -1000 && filter out strong dislikes) {follows_helix[i] = 0; continue;}
		//if (recommend["Tag prefs"] < 1000 && require at least one mandatory tag) {follows_helix[i] = 0; continue;}
		if (mapping k = extra_info[otheruid]) follows_helix[i] = strm = k | strm;
		if (string n = notes[(string)otheruid]) strm->notes = n;
		if (has_value(highlightids, otheruid)) strm->highlight = 1;
		if (!strm->url) strm->url = "https://twitch.tv/" + strm->user_login; //Is this always correct?
		int swap = otheruid < userid;
		array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[(string)(swap ? userid : otheruid)];
		int recent = time() - 86400 * 30;
		int ancient = time() - 86400 * 365;
		float raidscore = 0.0;
		int have_recent_outgoing = 0, have_old_incoming = 0;
		foreach (raids || ({ }), mapping raid) //Note that these may not be sorted correctly. Should we sort explicitly?
		{
			//write("DEBUG RAID LOG: %O\n", raid);
			//TODO: Translate these by timezone (if available)
			object time = Calendar.ISO.Second("unix", raid->time);
			raidscore *= 0.75; //If there are tons of raids, factor the most recent ones strongly, and weaken it into the past.
			if (swap != raid->outgoing) {
				strm->raids += ({sprintf(">%s %s raided %s", time->format_ymd(), raid->from, raid->to)});
				if (raid->time > recent) {have_recent_outgoing = 1; raidscore -= 200;}
				else if (raid->time > ancient) raidscore -= 50;
				else raidscore += 8; //"Oh yeah, I've known this person for years"
			}
			else {
				strm->raids += ({sprintf("<%s %s raided %s", time->format_ymd(), raid->from, raid->to)});
				if (raid->time > recent) raidscore += 100;
				else if (raid->time > ancient) {have_old_incoming = 1; raidscore += 100;}
				else raidscore += 10; //VERY old raid data has less impact than current.
			}
			if (!undefinedp(raid->viewers) && raid->viewers != -1)
				strm->raids[-1] += " with " + raid->viewers;
		}
		if (have_old_incoming && !have_recent_outgoing) raidscore += 100;
		if (raidscore != 0.0) recommend["Recent raids"] = (int)raidscore; //It's possible to get "Recent raids: 0" if it rounds to that, but it's unlikely.
		//For some reason, strm->raids[*][1..] doesn't work. ??
		sort(lambda(string x) {return x[1..];}(strm->raids[*]), strm->raids); //Sort by date, ignoring the </> direction marker
		strm->raids = Array.uniq2(strm->raids);
		//Make recommendations based on similarity to your stream
		if (your_stream) {
			int you = your_stream->viewer_count, them = strm->viewer_count;
			//With small viewer counts, percentages are over-emphasized. Bound to a group size.
			if (you < 10) you = 10;
			if (them < 10) them = 10;
			int scale = them * 100 / you;
			//Music streamers tend to have larger viewership. Rate their viewers
			//at 80% of what they actually are, as long as that would still leave
			//them showing more viewers than you, and as long as you're not also
			//streaming in Music (which would cancel out the effect).
			if (your_stream->game_id != strm->game_id && strm->category == "Music" && scale > 111)
				scale = scale * 8 / 10;
			if (scale >= 1000) recommend["Viewership (huge)"] = -50;
			if (scale >= 200) ; //Large, no bonus
			else if (scale > 100) recommend["Viewership (larger)"] = 100 - scale / 2; //Somewhat larger. Give 50 points if same size, diminishing towards 200%.
			else if (scale == 100) recommend["Viewership (same)"] = 50; //Either of the surrounding would give 50 points too, but we describe it differently.
			else recommend["Viewership (smaller)"] = scale / 2; //Smaller. Give 50 points if same size, diminishing towards 0%.
			//+100 for being in the same category
			if (your_stream->game_id == strm->game_id) recommend["Same category"] = 100;
			//Or +70 if both of you are in creative categories
			else if (creatives[your_stream->game_id] && creatives[strm->game_id]) recommend["Both in Creative"] = 70;
			//Common tags: 25 points apiece
			//Note that this will include language tags
			//Been seeing some 500 crashes that have been hard to track down. Is it b/c
			//one of the streams has no tags?? Maybe just gone live?? In any case, if
			//you don't have any tags, there won't be any common tags, so we're fine.
			if (your_stream->tag_ids && strm->tag_ids) {
				multiset common = (multiset)your_stream->tag_ids & (multiset)strm->tag_ids;
				if (sizeof(common)) {
					string desc = "Tags in common: " + G->G->all_stream_tags[((array)common)[*]]->name * ", ";
					recommend[desc] = 25 * sizeof(common);
				}
			}
		}
		//Up to 100 points for having just started, scaling down to zero at four hours of uptime
		if (strm->started_at) {
			int uptime = time() - Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", strm->started_at)->unix_time();
			recommend["Uptime"] = max(100 - uptime / 4 / 36, 0);
		}
		strm->recommend = `+(@values(recommend));
		if (req->variables->show_magic) strm->magic_breakdown = recommend; //Hidden query variable to debug the magic
	}
	//List 100 most recent raids.
	array all_raids = ({ });
	foreach (persist_status->path("raids"); string id; mapping raids) {
		if (id == (string)userid)
			foreach (raids; string otherid; array raids)
				all_raids += raids;
		else foreach (raids[(string)userid] || ({ }), mapping r)
			all_raids += ({r | (["outgoing": !r->outgoing])});
	}
	sort(all_raids->time, all_raids);
	follows_helix -= ({0}); //Remove self (already nulled out)
	sort(-follows_helix->recommend[*], follows_helix); //Sort by magic initially
	array tags = values(G->G->all_stream_tags); sort(tags->name, tags);
	return render_template("raidfinder.md", ([
		"vars": ([
			"follows": follows_helix, "all_tags": tags,
			"your_stream": your_stream, "highlights": highlights,
			"tag_prefs": tag_prefs, "MAX_PREF": MAX_PREF, "MIN_PREF": MIN_PREF,
			"all_raids": all_raids[<99..], "mode": "normal",
		]),
		"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
		"title": title,
	]));
}
