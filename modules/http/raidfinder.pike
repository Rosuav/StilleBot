inherit http_websocket;
/* Raid target finder
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - There's not going to be any easy UI for it, but it'd be great to have a "raided my friend"
    feature, where we can see any time that X raided Y where Y is one of my friends... hard.

TODO: Put a real space between tags so highlighting works correctly.
-- The browser seems to be ditching it for me. Not sure why, or how to stop it.
*/

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

multiset(string) creative_names = (<"Art", "Science & Technology", "Software and Game Development", "Food & Drink", "Music", "Makers & Crafting", "Beauty & Body Art">);
multiset(int) creatives = (<>);
int next_precache_request = time();

mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars) {return vars & (<"for">);}
	
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
		//TODO: Migrate this into persist_status->path("prefs", (string)req->misc->session->user->id, "raidnotes")
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
	//Provide some info on VOD durations for the front end to display graphically
	//Additionally (since this is a costly check anyway, so it won't add much), it
	//checks if the for= target is following them.
	if (string chan = req->variables->streamlength) {
		if (req->variables->precache) {
			//Low-priority request to populate the cache. Never more than 1 per second,
			//regardless of the number of connected clients.
			int now = time();
			int delay = ++next_precache_request - time();
			if (delay > 5) return jsonify((["error": "Wait a bit"])) | (["error": 425]);
			if (delay) yield(task_sleep(delay));
		}
		string html_title;
		if (!(int)chan) {
			//Client-side view. Return HTML and enough variables to open up the popup.
			html_title = "VOD lengths for " + chan;
			if (mixed ex = catch (chan = (string)yield(get_user_id(chan))))
				return (["error": 400, "data": "Unrecognized channel name " + chan]);
		}
		array vods = yield(get_helix_paginated("https://api.twitch.tv/helix/videos", (["user_id": chan, "type": "archive"])));
		if (string ignore = req->variables->ignore) //Ignore the stream ID for a currently live broadcast
			vods = filter(vods) {return __ARGS__[0]->stream_id != ignore;};
		//For convenience of the front end, do some parsing here in Pike.
		mapping ret = (["vods": map(vods) {mapping raw = __ARGS__[0];
			mapping vod = (["created_at": raw->created_at]);
			//Attributes in use: created_at, duration_seconds, week_correlation
			if (sscanf(raw->duration, "%dh%dm%ds", int h, int m, int s) == 3) vod->duration_seconds = h * 3600 + m * 60 + s;
			else if (sscanf(raw->duration, "%dm%ds", int m, int s) == 2) vod->duration_seconds = m * 60 + s;
			else if (sscanf(raw->duration, "%ds", int s)) vod->duration_seconds = s;
			//What do day-long streams look like?
			else {werror("**** UNKNOWN VOD DURATION FORMAT %O ****\n", raw->duration); vod->duration_seconds = 0;}

			//Would be nice to show the category too but I don't know where to get the data from. Kraken gets it.

			//Calculate how close this VOD is to the current time, modulo a week
			//If the VOD spans the current time, return zero. Otherwise, return the shorter of the time
			//until the start, and the time since the end.
			//Assumes no leap seconds.
			int howlongago = (time() - time_from_iso(vod->created_at)->unix_time()) % 604800;
			//Three options: the inverse of the time since it started; or the time since ending; or, if
			//time since ending is negative, zero.
			vod->week_correlation = max(min(604800 - howlongago, howlongago - vod->duration_seconds), 0);
			return vod;
		}]);
		ret->max_duration = max(@ret->vods->duration_seconds);
		//TODO: Calculate an approximate average VOD duration, which can (if available) be used in place of
		//the four hour threshold used for magic sort. Ignore outliers. Don't bother trying to combine
		//broken VODs together - too hard, too rare, let it adjust the average, it's fine.

		//Ping Twitch and check if there are any chat restrictions. So far I can't do this in bulk, but
		//it's great to be able to query them this way for the VOD length popup. Note that we're not
		//asking for mod settings here, so non_moderator_chat_delay won't be in the response.
		mapping settings = yield(twitch_api_request("https://api.twitch.tv/helix/chat/settings?broadcaster_id=" + chan));
		if (arrayp(settings->data) && sizeof(settings->data)) ret->chat_settings = settings->data[0];

		//Hang onto this info in cache, apart from is_following (below).
		ret->cache_time = time();
		persist_status->path("raidfinder_cache")[chan] = ret;
		persist_status->save();

		string chanid = req->variables["for"];
		if (chanid && chanid != (string)logged_in->?id && chanid != chan) {
			//If you provided for=userid, also show whether the target is following this stream. Gonna die when the deprecation concludes.
			mapping info = yield(twitch_api_request(sprintf("https://api.twitch.tv/helix/users/follows?from_id=%s&to_id=%s", chanid, chan)));
			if (sizeof(info->data)) {
				ret->is_following = info->data[0];
				object howlong = time_from_iso(ret->is_following->followed_at)->distance(Calendar.ISO.now());
				string length = "less than a day";
				foreach (({
					({Calendar.ISO.Year, "year"}),
					({Calendar.ISO.Month, "month"}),
					({Calendar.ISO.Day, "day"}),
				}), [program span, string desc])
					if (int n = howlong / span) {
						length = sprintf("%d %s%s", n, desc, "s" * (n > 1));
						break;
					}
				ret->is_following->follow_length = length;
			}
			else ret->is_following = (["from_id": chanid]);
		}

		//Publish this info to all socket-connected clients that care.
		string msg = Standards.JSON.encode((["cmd": "chanstatus", "channelid": chan, "chanstatus": ret]));
		foreach (websocket_groups[""], object sock) if (sock && sock->state == 1) {
			//See if the client is interested in this channel
			catch {
				mapping conn = sock->query_id(); //If older Pike, don't bother with the check, just push it out anyway
				if (!conn->want_streaminfo || !has_index(conn->want_streaminfo, chan)) continue;
			};
			sock->send_text(msg);
		}

		if (html_title) return render(req, ([
			"vars": (["mode": "vodlength", "vodinfo": ret]),
			"sortorders": "<script type=module src=\"" + G->G->template_defaults["static"]("raidfinder.js") + "\"></script>",
			"title": html_title,
		]));
		return jsonify(ret);
	}
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
			array lines = ({ });
			foreach (sort(online), string name) {
				object chan = G->G->irc->channels["#" + name];
				if (chan) lines += ({sprintf("<li class=%s><a href=\"/raidfinder?for=%s\">%<s</a></li>",
					chan->config->active ? "bot": "monitor",
					name,
				)});
			}
			return (["data": "<style>.bot::marker{color:green}.monitor::marker{color:orange}body{font-size:16pt}</style><ul>" + lines * "\n" + "</ul><p>See tiled: <a href=\"raidfinder?login=demo\">login=demo</a></p>", "type": "text/html"]);
		}
		if (userid == (string)(int)userid) userid = (int)userid;
		else userid = yield(get_user_id(chan));
	}
	else if (logged_in) userid = (int)logged_in->id; //Raidfind for self if logged in.
	//TODO: Based on the for= or the logged in user, determine whether raids are tracked.
	mapping raids = ([]);
	array follows_helix;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for=
	//annotation. For notes attached to a channel, that channel's ID is
	//used; other forms of notes are attached to specific keywords. In a
	//previous iteration of this, notes ID 0 was used for "highlight".
	mapping notes = persist_status->path("raidnotes")[(string)logged_in->?id] || ([]);
	array highlightids = ({ });
	if (notes["0"]) notes->highlight = m_delete(notes, "0"); //Migrate
	if (notes->highlight) highlightids = (array(int))(notes->highlight / "\n");
	string highlights;
	if (req->variables->allfollows)
	{
		//Show everyone that you follow (not just those who are live), in an
		//abbreviated form, mainly for checking notes.
		if (mapping resp = ensure_login(req, "user:read:follows")) return resp;
		array f = yield(get_helix_paginated("https://api.twitch.tv/helix/channels/followed",
				(["user_id": (string)req->misc->session->user->id])));
		//TODO: Make a cleaner way to fragment requests - we're gonna need it.
		array(array(string)) blocks = f->broadcaster_id / 100.0;
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
		return render(req, ([
			"vars": (["ws_group": "", "follows": follows_helix, "your_stream": 0, "highlights": highlights, "all_raids": ({}), "mode": "allfollows"]),
			"sortorders": ({"Channel Creation", "Follow Date", "Name"}) * "\n* ",
		]));
	}
	string login, disp, raidbtn = "";
	if (logged_in && (int)logged_in->id == userid) {
		login = logged_in->login; disp = logged_in->display_name;
		//Do we have authentication to start raids? Note that this is
		//irrelevant if we're doing a raidfind for someone else.
		multiset havescopes = req->misc->session->?scopes || (<>);
		if (havescopes["channel:manage:raids"]) raidbtn = "[Raid now!](:#raidnow)";
		else raidbtn = "[Authenticate to raid automatically](:.twitchlogin data-scopes=channel:manage:raids)";
	}
	else if (mapping user = userid && G->G->user_info[userid])
	{
		login = user->login || user->name; //helix || kraken
		disp = user->display_name;
	}
	array users = yield(get_users_info(highlightids));
	highlights = users->login * "\n";
	string title = "Followed streams";
	//Special searches, which don't use your follow list (and may be possible without logging in)
	if (req->variables->raiders || req->variables->categories || req->variables->login || req->variables->train || req->variables->highlights) {
		mapping args = ([]);
		if (req->variables->raiders) {
			//Raiders mode (categories omitted but "?raiders" specified). Particularly useful with a for= search.
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
		}
		else if (req->variables->highlights) {
			//Restrict your follow list to those you have highlighted.
			args->user_id = (array(string))highlightids;
			title = "Highlighted channels";
		}
		else if (req->variables->login == "demo") {
			//Like specifying login= for each of the channels that I bot for
			//Note that this excludes connected but not active (monitor-only) channels.
			args->user_login = ({ });
			foreach (persist_config->path("channels"); string chan; mapping info)
				if (chan[0] != '!') args->user_login += ({chan});
			title = "This bot's channels";
		}
		else if (req->variables->login) {
			//TODO: Load up the specified users even if they're not currently online.
			//This may involve stubbing out things like the thumbnail and viewership.
			//Once done, though, this could be used for various things incl adding a
			//note to a stream, or incorporated into the above raiders code, giving
			//options of "raiders currently online" and "all raiders".
			args->user_login = req->variables->login;
			//Specify ?login=X&login=Y or ?login=X,Y for multiples
			if (stringp(args->user_login) && has_value(args->user_login, ",")) args->user_login /= ",";
			title = "Detailed stream info";
		}
		else if (req->variables->train) {
			//Using a particular user's (current) raid train as a user set, scan
			//for streams who are currently live. Ignores the schedule and just
			//uses the list of all_casters.
			string owner = req->variables->train;
			if (!(int)owner) owner = (string)yield(get_user_id(owner));
			mapping trncfg = persist_status->path("raidtrain")[owner]->?cfg;
			array casters = trncfg->?all_casters;
			if (!casters) return "No such raid train - check the link and try again";
			args->user_id = (array(string))casters;
			title = "Raid Train: " + (trncfg->title || "(untitled)");
		}
		else switch (req->variables->categories) {
			default: { //For ?categories=Art,Food%20%26%20Drink - explicit categories
				array cats = yield(get_helix_paginated("https://api.twitch.tv/helix/games", (["name": req->variables->categories / ","])));
				if (sizeof(cats)) {
					args->game_id = (array(string))cats->id;
					title = cats->name * ", " + " streams";
					break;
				}
				//Else fall through. Any sort of junk category name, treat it as if it's "?categories"
			}
			case "": case "categories": case "flush": { //For ?categories and ?categories= modes, show those you follow
				if (mapping resp = ensure_login(req, "user_read")) return resp;
				//20220216: This still isn't available in Helix, so what we do is cache it ourselves.
				//Populating this cache is outside the scope of this module.
				array cats = persist_status->path("user_followed_categories")[req->misc->session->user->id];
				if (!cats || req->variables->categories == "flush") {
					//Try to populate the cache using an external lookup. As of 20220216,
					//this lookup will be done using the legacy Kraken API, but will then
					//be cached so the data is retained post-shutdown.
					persist_status->path("user_followed_categories")[req->misc->session->user->id] = cats;
				}
				args->game_id = cats;
				title = "Followed categories";
				break;
			}
		}
		[array streams, mapping self] = yield(Concurrent.all(
			get_helix_paginated("https://api.twitch.tv/helix/streams", args),
			twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + userid),
		));
		array(string) ids = streams->user_id + ({(string)userid});
		follows_helix = streams + self->data;
		//If you follow a large number of categories, or a single large category,
		//there could be rather a lot of IDs. Fetch in blocks.
		users = yield(fracture(ids, 100) {return get_helix_paginated("https://api.twitch.tv/helix/users", (["id": __ARGS__[0]]));});
	}
	else {
		if (mapping resp = ensure_login(req, "user:read:follows")) return resp;
		follows_helix = yield(get_helix_paginated("https://api.twitch.tv/helix/streams/followed",
			(["user_id": (string)req->misc->session->user->id]),
			(["Authorization": "Bearer " + req->misc->session->token])));
		//Ensure that we have the user we're looking up (yourself, unless it's a for=USERNAME raidfind)
		follows_helix += yield(get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": (string)userid])));
		//Grab some additional info from the Users API, including profile image and
		//whether the person is partnered or affiliated.
		users = yield(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": follows_helix->user_id + ({(string)userid})])));
	}
	mapping your_stream;
	foreach (follows_helix, mapping strm)
		if ((int)strm->user_id == userid) your_stream = strm;
	mapping(int:mapping(string:mixed)) extra_info = ([]);
	foreach (users, mapping user)
		extra_info[(int)user->id] = ([
			"broadcaster_type": user->broadcaster_type,
			"profile_image_url": user->profile_image_url,
		]) | (extra_info[(int)user->id] || ([]));
	//Okay! Preliminaries done. Let's look through the Helix-provided info and
	//build up a final result.
	mapping(string:int) tag_prefs = notes->tags || ([]);
	mapping cached_status = persist_status->path("raidfinder_cache");
	foreach (follows_helix; int i; mapping strm)
	{
		mapping(string:int) recommend = ([]);
		foreach (strm->tags || ({ }), string tag)
			if (int pref = tag_prefs[tag]) recommend["Tag prefs"] += PREFERENCE_MAGIC_SCORES[pref];
		strm->category = G->G->category_names[strm->game_id] || strm->game_name;
		strm->raids = raids[strm->user_login] || ({ });
		if (mapping st = cached_status[strm->user_id]) strm->chanstatus = st;
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
			raidscore *= 0.85; //If there are tons of raids, factor the most recent ones strongly, and weaken it into the past.
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
			if (your_stream->tags && strm->tags) {
				array common = your_stream->tags & strm->tags;
				if (sizeof(common))
					recommend["Tags in common: " + common * ", "] = 25 * sizeof(common);
			}
		}
		//Up to 100 points for having just started, scaling down to zero at four hours of uptime
		//TODO: If we have channel info with an average VOD duration, calculated no more than a
		//week ago, use that instead of four hours.
		if (strm->started_at) {
			int uptime = time() - time_from_iso(strm->started_at)->unix_time();
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
	return render(req, ([
		"vars": ([
			"ws_group": "",
			"on_behalf_of_userid": userid, //The same userid as you're logged in as, unless for= is specified
			"follows": follows_helix,
			"all_tags": ({ }), //Deprecated as of 20230127 - tags by ID are no longer a thing.
			"your_stream": your_stream, "highlights": highlights,
			"tag_prefs": tag_prefs, "MAX_PREF": MAX_PREF, "MIN_PREF": MIN_PREF,
			"all_raids": all_raids[<99..], "mode": "normal",
		]),
		"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
		"title": title,
		"raidbtn": raidbtn,
	]));
}

//Record what the client is interested in hearing about. It's not consistent or coherent
//enough to use the standard 'groups' system, as a single client may be interested in
//many similar things, but it's the same kind of idea.
void websocket_cmd_interested(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (mappingp(msg->want_streaminfo)) conn->want_streaminfo = msg->want_streaminfo;
}

//Note that the front end won't send this message if you're doing a for= raidfind, but
//if you fiddle around and force the message to be sent, all that will happen is that
//the raid is started for YOUR channel, not the one you're raidfinding for.
void websocket_cmd_raidnow(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	multiset havescopes = conn->session->?scopes || (<>);
	if (!havescopes["channel:manage:raids"]) return;
	string id = conn->session->?user->?id; if (!id) return;
	int target = (int)msg->target; if (!target) return; //Ensure that it casts to int correctly
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?from_broadcaster_id=%s&to_broadcaster_id=%d",
			id, target),
		(["Authorization": "Bearer " + conn->session->token]),
		(["method": "POST", "return_errors": 1]),
	)->then() {mapping result = __ARGS__[0];
		if (result->error) {
			//Don't give too much info here, not sure what would leak private data
			conn->sock->send_text(Standards.JSON.encode((["cmd": "update", "raidstatus": "Raid failed."]), 4));
			return;
		}
		conn->sock->send_text(Standards.JSON.encode((["cmd": "update", "raidstatus": "RAIDING!"]), 4));
		//It'd be nice to have something that notifies the user when the raid has actually gone through,
		//but that would require an additional webhook which we'd want to dispose of later.
	};
}

continue Concurrent.Future|int guess_user_id(string name, int|void fastonly) {
	//There are a few that I know have renamed.
	string newname = ([
		"ratpixie": "pixalicious_",
		"jib410_": "jib410",
		"zladyluthien": "sarahburnsstudio",
		"sezzadactyl": "sezza",
		"caneofbyrna": "byrna",
		"imperialgrrl": "imperial",
		"btnfoxtv": "buttonfox",
		"magicalmooniecosplay": "magicalmoonie",
		"mrcortus": "sircort",
		"silverjd14": "silverjd",
		"cascadiaqueen": "cascadiastudio",
		"terrielynn": "tinymamafox",
		"lizabelleac": "lizabelle",
		"thatlapres": "lapres",
		"movermedia": "movercwl",
		"kuri0uskitteh": "kuri0uskreations",
		"vivscute": "vivyaong",
		"sannimaya": "sannihalla", "sanni_maya": "sannihalla",
		"blipsqueektheclown": "blipsqueek",
		"xtzharkz": "xtzshark",
		"rik_leah": "rikonair",
		"tijka_": "tijka",
		"getinmymailbox": "freckledfiberworks",
		"behindthescenes": "moosedoesstuff",
		"denaemoon": "fiyunae",
		"lady_goggles": "ladygoggles",
	])[lower_case(name)];
	if (newname) name = newname;
	else if (fastonly) return 0;
	catch {
		int id = yield(get_user_id(name));
		if (id) return id; //If the name currently exists, hope that it is the right person.
	};
	//Otherwise, try to look up our history of old names
	mapping n2u = G->G->name_to_uid;
	if (n2u[name]) return (int)n2u[name];
	//Otherwise, bail.
	return 0;
}

continue Concurrent.Future|int retrofit_raids(int|void fastlookups) {
	mapping failed_lookups = ([]), sources = ([]);
	foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n"; int i; string raid)
	{
		sscanf(raid, "[%d-%d-%d %d:%d:%d] %s => %s", int y, int m, int d, int h, int mm, int s, string from, string to);
		if (!to) continue;
		int have_viewers = sscanf(to, "%s with %d", to, int viewers) > 1;
		if (failed_lookups[lower_case(from)] || failed_lookups[lower_case(to)]) continue;
		//First up, figure out the IDs for the channels.
		//If anyone has renamed, this will be hard.
		int fromid = yield(guess_user_id(from));
		if (!fromid) {
			//Maybe the channel I track renamed, or maybe the line failed to parse
			write("UNKNOWN SOURCE: %s\n", raid);
			continue;
		}
		int toid = yield(guess_user_id(to, fastlookups));
		int ts = mktime(s, mm, h, d, m - 1, y - 1900);
		if (!toid) {
			if (fastlookups) continue;
			write("%s %s [%d] => %s [%d]\n", ctime(ts)[..<1], from, fromid, to, toid);
			write("--- User ids not found ---\n");
			failed_lookups[lower_case(to)] = from;
			sources[from] += ({to});
			continue;
		}
		int outgoing = fromid < toid;
		string base = outgoing ? (string)fromid : (string)toid;
		string other = outgoing ? (string)toid : (string)fromid;
		mapping raids = persist_status->path("raids", base);
		int found = 0;
		foreach (raids[other] || ({ }), mapping r) {
			if (r->outgoing != outgoing) continue;
			if (r->time < ts - 60 || r->time > ts + 60) continue;
			found = 1;
			break;
		}
		if (found) continue;
		//Not found! Add it to the pile.
		write("%s %s [%d] => %s [%d] -- not found -- adding\n", ctime(ts)[..<1], from, fromid, to, toid);
		if (!raids[other]) raids[other] = ({ });
		raids[other] += ({([
			"time": ts,
			"from": from, "to": to,
			"outgoing": outgoing,
			"viewers": have_viewers ? -1 : (int)viewers,
			"reconstructed": 1, //Flag these as having been built from the text file.
		])});
		sort(raids[other]->time, raids[other]);
	}
	write("Migration complete. %O\n", sources);
	m_delete(persist_status->path("raids"), "0");
	persist_status->save();
	return 0;
}

protected void create(string name) {
	::create(name);
	//spawn_task(retrofit_raids()); //Uncomment to do a full migration pass. CAUTION: Takes a while.
	//spawn_task(retrofit_raids(1)); //Uncomment to do a fast(ish) migration pass, just getting renames.
	//Clean out the raid finder cache of anything more than two weeks old
	mapping cache = persist_status["raidfinder_cache"] || ([]);
	int stale = time() - 86400 * 14;
	foreach (indices(cache), string uid) {
		if (cache[uid]->cache_time < stale) m_delete(cache, uid);
	}
	persist_status->save();
}
