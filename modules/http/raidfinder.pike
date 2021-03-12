inherit http_endpoint;
/* Raid target finder
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - There's not going to be any easy UI for it, but it'd be great to have a "raided my friend"
    feature, where we can see any time that X raided Y where Y is one of my friends... hard.

Possible enhancement: Tag filtering or recommendations.
- For filtering, allow both positive and negative
  - Require tag "English"
  - Exclude any with tag "Speedrun"
- For recommendations, allow the strength to be set??
  - Will affect Magic sort, and may also be a separate sort option
  - For calibration, "same category" is worth 100 points, and each tag in common with you is 25 points.
  - Default strength of tag recommendation should probably be 100 +/- 50
  - Tag recommendations can be negative, penalizing those streams. It's probably best to keep
    most tag usage positive though.
  - https://api.twitch.tv/helix/tags/streams - all tags - about 500ish, of which about 250 are automatic


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

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "user_read")) return resp;
	if (req->request_type == "POST")
	{
		//Update notes
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
	int userid = (int)req->misc->session->user->id;
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
	//TODO: Based on the for= or the logged in user, determine whether raids are tracked.
	mapping raids = ([]);
	array follows_kraken, follows_helix;
	mapping(int:mapping(string:mixed)) extra_kraken_info = ([]);
	mapping your_stream;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for=
	//annotation. For notes attached to a channel, that channel's ID is
	//used; other forms of notes are attached to specific keywords. In a
	//previous iteration of this, notes ID 0 was used for "highlight".
	mapping notes = persist_status->path("raidnotes")[(string)req->misc->session->user->id] || ([]);
	array highlightids = ({ });
	if (notes["0"]) notes->highlight = m_delete(notes, "0"); //Migrate
	if (notes->highlight) highlightids = (array(int))(notes->highlight / "\n");
	string highlights;
	if (req->variables->allfollows)
	{
		//Show everyone that you follow (not just those who are live), in an
		//abbreviated form, mainly for checking notes.
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
	string login = req->misc->session->user->login, disp = req->misc->session->user->display_name;
	if (mapping user = userid != (int)req->misc->session->user->id && G->G->user_info[userid])
	{
		login = user->login || user->name; //helix || kraken
		disp = user->display_name;
	}
	foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n", string raid)
	{
		sscanf(raid, "[%d-%d-%d %*d:%*d:%*d] %s => %s", int y, int m, int d, string from, string to);
		if (!to) continue;
		if (y >= 2021) break; //Ignore newer entries and rely on the proper format (when should the cutoff be?)
		if (from == login) raids[lower_case(to)] += ({sprintf(">%d-%02d-%02d %s raided %s", y, m, d, from, to)});
		if (to == disp) raids[from] += ({sprintf("<%d-%02d-%02d %s raided %s", y, m, d, from, to)});
	}
	array users = yield(get_users_info(highlightids));
	highlights = users->login * "\n";
	string title = "Followed streams";
	//Category search - show all streams in the categories you follow
	if (req->variables->categories) {
		array gameids;
		if (!(<"", "categories">)[req->variables->categories]) {
			array cats = yield(get_helix_paginated("https://api.twitch.tv/helix/games", (["name": req->variables->categories / ","])));
			if (sizeof(cats)) {gameids = cats->id; title = cats->name * ", " + " streams";}
		}
		if (!gameids) {
			mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/users/" + req->misc->session->user->id + "/follows/games"));
			gameids = (array(string))info->follows->game->_id;
			title = "Followed categories";
		}
		[array streams, mapping self] = yield(Concurrent.all(
			get_helix_paginated("https://api.twitch.tv/helix/streams", (["game_id": (array(string))gameids])),
			twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + userid),
		));
		array(string) ids = streams->user_id + ({(string)userid});
		//Map channel list to Kraken so we get both sets of info
		follows_helix = streams + self->data;
		//If you follow a large number of categories, or a single large category,
		//there could be rather a lot of IDs. Note that, in theory, this could
		//ALL be done with Concurrent.all(), but I don't want to risk having an
		//arbitrary number of simultaneous requests; it's very hard to predict
		//the impact of rate-limiting.
		follows_kraken = ({ }); users = ({ });
		foreach (ids / 100.0, array block) {
			mapping ret = yield(Concurrent.all(
				twitch_api_request("https://api.twitch.tv/kraken/streams/?channel=" + block * ","),
				get_helix_paginated("https://api.twitch.tv/helix/users", (["id": block])),
			));
			follows_kraken += ret[0]->streams; users += ret[1];
		}
	}
	else {
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
	multiset need_tags = (<>);
	foreach (follows_helix, mapping strm)
	{
		foreach (strm->tag_ids || ({ }), string tag)
			if (!G->G->all_stream_tags[tag]) need_tags[tag] = 1;
	}
	if (sizeof(need_tags)) {
		//Normally we'll have all the tags from the check up above, but in case, we catch more here.
		write("Fetching %d tags...\n", sizeof(need_tags));
		update_tags(yield(get_helix_paginated("https://api.twitch.tv/helix/tags/streams", (["tag_id": (array)need_tags]))));
	}
	foreach (follows_kraken, mapping strm)
		extra_kraken_info[strm->channel->_id] = ([
			"profile_image_url": strm->channel->logo,
			"url": strm->channel->url,
			//strm->video_height and strm->average_fps might be of interest
		]);
	foreach (users, mapping user) broadcaster_type[(int)user->id] = user->broadcaster_type;
	//Okay! Preliminaries done. Let's look through the Helix-provided info and
	//build up a final result.
	mapping tag_prefs = notes->tags || ([]);
	foreach (follows_helix; int i; mapping strm)
	{
		int recommend = 0;
		array tags = ({ });
		foreach (strm->tag_ids || ({ }), string tagid) {
			if (mapping tag = G->G->all_stream_tags[tagid]) tags += ({tag});
			if (int pref = tag_prefs[tagid]) recommend += PREFERENCE_MAGIC_SCORES[pref];
		}
		strm->tags = tags;
		strm->category = G->G->category_names[strm->game_id];
		strm->raids = raids[strm->user_login] || ({ });
		int otheruid = (int)strm->user_id;
		if (otheruid == userid) {your_stream = strm; follows_helix[i] = 0; continue;}
		//TODO: Configurable hard tag requirements
		//if (recommend <= -1000 && filter out strong dislikes) {follows_helix[i] = 0; continue;}
		//if (recommend < 1000 && require at least one mandatory tag) {follows_helix[i] = 0; continue;}
		if (mapping k = extra_kraken_info[otheruid]) follows_helix[i] = strm = k | strm;
		if (string t = broadcaster_type[otheruid]) strm->broadcaster_type = t;
		if (string n = notes[(string)otheruid]) strm->notes = n;
		if (has_value(highlightids, otheruid)) strm->highlight = 1;
		int swap = otheruid < userid;
		array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[(string)(swap ? userid : otheruid)];
		int recent = time() - 86400 * 30;
		int ancient = time() - 86400 * 365;
		foreach (raids || ({ }), mapping raid)
		{
			//write("DEBUG RAID LOG: %O\n", raid);
			//TODO: Translate these by timezone (if available)
			object time = Calendar.ISO.Second("unix", raid->time);
			if (swap != raid->outgoing) {
				strm->raids += ({sprintf(">%s %s raided %s", time->format_ymd(), raid->from, raid->to)});
				if (raid->time > recent) recommend -= 200;
				else if (raid->time > ancient) recommend -= 50;
				else recommend += 8; //"Oh yeah, I've known this person for years"
			}
			else {
				strm->raids += ({sprintf("<%s %s raided %s", time->format_ymd(), raid->from, raid->to)});
				if (raid->time > recent) recommend += 100;
				else if (raid->time > ancient) recommend += 200;
				else recommend += 10; //VERY old raid data has less impact than current.
			}
			if (!undefinedp(raid->viewers) && raid->viewers != -1)
				strm->raids[-1] += " with " + raid->viewers;
		}
		//For some reason, strm->raids[*][1..] doesn't work. ??
		sort(lambda(string x) {return x[1..];}(strm->raids[*]), strm->raids); //Sort by date, ignoring the </> direction marker
		strm->raids = Array.uniq2(strm->raids);
		//Stream recommendation level (which defines the default sort order)
		if (your_stream) {
			int you = your_stream->viewer_count;
			if (!you) {
				//If you have no viewers, it's hard to scale things, so we
				//pick an arbitrary figure to use.
				if (strm->viewers < 20) recommend += 20 - strm->viewers;
			}
			else {
				int scale = strm->viewers * 100 / you;
				if (scale >= 140) ; //Large, no bonus
				else if (scale >= 100) recommend += 70 - scale / 2; //Slightly larger. Give 20 points if same size, diminishing towards 140%.
				else recommend += scale / 5; //Smaller. Give 20 points if same size, diminishing towards 0%.
			}
			multiset(string) creatives = (<"Art", "Science & Technology", "Food & Drink", "Music", "Makers & Crafting", "Beauty & Body Art">);
			//+100 for being in the same category
			if (your_stream->category == strm->game) recommend += 100;
			//Or +70 if both of you are in creative categories
			else if (creatives[your_stream->category] && creatives[strm->game]) recommend += 70;
			//Common tags: 25 points apiece
			//Note that this will include language tags
			//Been seeing some 500 crashes that have been hard to track down. Is it b/c
			//one of the streams has no tags?? Maybe just gone live?? In any case, if
			//you don't have any tags, there won't be any common tags, so we're fine.
			if (your_stream->tag_ids && strm->tag_ids)
				recommend += 25 * sizeof((multiset)your_stream->tag_ids & (multiset)strm->tag_ids);
		}
		//Up to 100 points for having just started, scaling down to zero at four hours of uptime
		if (strm->started_at) {
			int uptime = time() - Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", strm->started_at)->unix_time();
			if (uptime < 4 * 3600) recommend += uptime / 4 / 36;
		}
		strm->recommend = recommend;
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
