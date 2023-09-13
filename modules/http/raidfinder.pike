inherit http_websocket;
inherit irc_callback;
inherit annotated;
inherit builtin_command;
/* Raid target finder
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - There's not going to be any easy UI for it, but it'd be great to have a "raided my friend"
    feature, where we can see any time that X raided Y where Y is one of my friends... hard.
*/

constant MAX_PREF = 3, MIN_PREF = -3;
constant PREFERENCE_MAGIC_SCORES = ({
	0, //Must have 0 for score 0
	50, 250, 1000, //Positive ratings
	0, 0, 0, 0, //Shims, just in case (shouldn't be necessary)
	-1000, -250, -50, //Negative ratings
});

multiset(string) creative_names = (<"Art", "Science & Technology", "Software and Game Development", "Food & Drink", "Music", "Makers & Crafting", "Beauty & Body Art">);
multiset(int) creatives = (<>);
int next_precache_request;
@retain: mapping raid_suggestions = ([]);

array(mapping) prune_raid_suggestions(string id) {
	if (!raid_suggestions[id]) return ({ });
	int stale = time() - 15*60; //After fifteen minutes, they expire
	foreach (raid_suggestions[id]; int i; mapping sugg) {
		if (sugg->suggested_at < stale) raid_suggestions[id][i] = 0;
	}
	raid_suggestions[id] -= ({0});
	//Collapse similar suggestions and make arrays of their suggestors.
	//This is a naive O(n²) algorithm because I don't expect crazy numbers
	//of suggestions for a single target streamer within 15 minutes!!
	array sugg = raid_suggestions[id];
	array ret = ({ });
	foreach (sugg->id, string id) {
		if (has_value(ret->id, id)) continue;
		array this_target = filter(sugg) {return __ARGS__[0]->id == id;};
		ret += ({this_target[-1] | (["suggested_by": this_target->suggested_by])});
	}
	return ret;
}

mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars) {return vars & (<"for">);}

constant markdown_menu = #"# Raid finder modes
* [Your follow list](raidfinder). This is the normal and default mode, and shows
  your own follow list sorted according to your own channel's statistics. Requires
  login. Can give recent raid statistics.
* [Your stream team(s), if any](raidfinder?team=). If you're a member of any teams,
  this will show you everyone in them who's live! (Excluding yourself.)
* <form><label>Recommendations for another streamer: <input name=for size=20></label> <input type=submit value=View></form>
  Show your follow list, but compare against another channel's statistics. Requires
  login. Can give recent raid statistics, if bot is active for the target channel.
* <form><label>Browse a category: <input name=categories size=20></label> <input type=submit value=Browse></form>
  Show any category - note that large categories may take a while to load! Does not
  require a login.
* <form><label>Explore a stream team: <input name=team size=20></label> <input type=submit value=View></form>
  Show any stream team by name (look in the URL - not always the same as the display).
* [Pixel Plush users](raidfinder?categories=pixelplush) - everyone who's currently
  using games from [Pixel Plush](https://pixelplush.dev). The same channels as are
  seen on their homepage carousel. No login required.
* [The bot's channels](raidfinder?login=demo) - only those channels for which the
  bot is active. Requires no login. Suitable as a demo but not very useful.
* [Summary of everyone you follow](raidfinder?allfollows) for note taking. Includes
  channels not currently online; can be slow to load.
* [Return the Favour](raidfinder?raiders) - list everyone currently live who has
  raided you. Add `for=otherstreamer`?? TODO.
* [Highlighted streamers](raidfinder?highlights) - only those streamers you've
  listed in your highlight list.

<style>li {margin-top: 0.5em;}</style>
";
//Modes train and tradingcards are omitted as they are more usefully accessed from
//their corresponding pages. Also login=user,user,user omitted as not useful.

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	System.Timer tm = System.Timer();
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
					//Hack: "<viewership>" is used for the "hide viewer counts" setting
					if (id != "" && id[0] == '<') pref = pref < 0 ? -1 : 0;
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
			if (next_precache_request < now) next_precache_request = now;
			int delay = next_precache_request - now;
			if (delay > 5) return jsonify((["error": "Wait a bit"])) | (["error": 425]);
			if (delay) yield(task_sleep(delay));
			++next_precache_request;
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
			//TODO: Make it possible for a broadcaster to grant user:read:follows, which would allow such recommendations.
			//TODO also: Use the same cache that tradingcards.pike uses. Maybe move the code to poll.pike?
			//TODO: Move this to poll as a generic "is X following Y" call, which will be cached.
			//It can then use EITHER form of the query - if we have X's user:read:follows or Y's moderator:read:followers
			//Might need a way to locate a moderator though. Or go for the partial result with intrinsic auth??
			array creds = yield(token_for_user_id_async((int)chanid));
			array scopes = creds[1] / " ";
			if (has_value(scopes, "user:read:follows")) {
				mapping info = yield(twitch_api_request(sprintf("https://api.twitch.tv/helix/channels/followed?user_id=%s&broadcaster_id=%s", chanid, chan),
					(["Authorization": "Bearer " + creds[0]])));
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
					ret->to_name = ret->is_following->broadcaster_name; //Old API: from_name, to_name (and their IDs)
					ret->from_name = yield(get_user_info((int)chanid))->display_name; //This might not be necessary; check the front end.
				}
				else ret->is_following = (["from_id": chanid]);
			}
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
	if (req->variables->menu) {
		//Show a menu of available raid finder modes.
		return render_template(markdown_menu, ([]));
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
				if (chan) lines += ({sprintf("<li class=bot><a href=\"/raidfinder?for=%s\">%<s</a></li>",
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
	array follows_helix;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for=
	//annotation. For notes attached to a channel, that channel's ID is
	//used; other forms of notes are attached to specific keywords. In a
	//previous iteration of this, notes ID 0 was used for "highlight".
	mapping notes = persist_status->has_path("raidnotes", (string)logged_in->?id) || ([]);
	array highlightids = ({ });
	if (notes["0"]) notes->highlight = m_delete(notes, "0"); //Migrate
	if (notes->highlight) highlightids = (array(int))(notes->highlight / "\n");
	string highlights;
	mapping annotations = ([]); //Annotations are provided by the server under select circumstances
	if (req->variables->allfollows)
	{
		//Show everyone that you follow (not just those who are live), in an
		//abbreviated form, mainly for checking notes.
		if (mapping resp = ensure_login(req, "user:read:follows")) return resp;
		array f = yield(get_helix_paginated("https://api.twitch.tv/helix/channels/followed",
				(["user_id": (string)req->misc->session->user->id])));
		follows_helix = yield(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": f->broadcaster_id])));
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
			"vars": ([
				"ws_group": "", "follows": follows_helix, "your_stream": 0, "highlights": highlights,
				"all_raids": ({}), "raid_suggestions": 0, "mode": "allfollows", "on_behalf_of_userid": userid,
			]),
			"sortorders": ({"Channel Creation", "Follow Date", "Name"}) * "\n* ",
		]));
	}
	string login, disp, raidbtn = logged_in ? "[Suggest](:#suggestraid)" : "";
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
	if (req->variables->raiders || req->variables->categories || req->variables->login || req->variables->train || req->variables->highlights || req->variables->team) {
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
			args->user_login = ({ });
			foreach (list_channel_configs(), mapping info)
				if (info->login && info->login[0] != '!') args->user_login += ({info->login});
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
			mapping trncfg = persist_status->has_path("raidtrain", owner, "cfg");
			array casters = trncfg->?all_casters;
			if (!casters) return "No such raid train - check the link and try again";
			args->user_id = (array(string))casters;
			title = "Raid Train: " + (trncfg->title || "(untitled)");
		}
		else if (string|array team = req->variables->team) {
			//Team may be an array (team=X&team=Y), a comma-separated list (team=X,Y - also
			//the obvious form team=X counts as this), or blank (team=) meaning "my teams".
			if (team == "") {
				if (mapping resp = ensure_login(req, "user_read")) return resp;
				team = yield(twitch_api_request("https://api.twitch.tv/helix/teams/channel?broadcaster_id=" + userid))->data->team_name || ({ });
			}
			else if (stringp(team)) team /= ",";
			//team should now be an array of team names, regardless of how it was input
			args->user_id = ({ });
			array team_display_names = ({ });
			foreach (team; int i; string t) catch {
				mixed data = yield(twitch_api_request("https://api.twitch.tv/helix/teams?name=" + t))->data; //what if team name has specials?
				if (!sizeof(data)) continue; //Probably team not found
				team_display_names += ({data[0]->team_display_name});
				args->user_id += data[0]->users->user_id;
			};
			if (!sizeof(args->user_id)) title = "Stream Team not found"; //Most likely this is because you misspelled the team name
			else if (sizeof(team_display_names) > 1) title = "Stream Teams: " + team_display_names * ", ";
			else title = "Stream Team: " + team_display_names[0];
		}
		else if (mapping tradingcards = persist_status->path("tradingcards", "collections")[lower_case(req->variables->categories)]) {
			//categories=Canadian to see who's live from the Canadian Streamers collection of trading cards
			title = "Active " + tradingcards->label + " streamers";
			args->user_id = tradingcards->streamers;
		}
		else switch (req->variables->categories) {
			case "pixelplush": { //categories=pixelplush - use an undocumented API to find people playing the !drop game etc
				object res = yield(Protocols.HTTP.Promise.get_url(
					"https://api.pixelplush.dev/v1/analytics/sessions/live"
				));
				mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
				if (!arrayp(data)) title = "Unable to fetch";
				else {
					title = "Active Pixel Plush streamers";
					foreach (data, mapping strm) annotations[strm->stream->userId] += ({strm->theme});
					foreach (annotations; string uid; array anno)
						annotations[uid] = Array.uniq(anno);
					args->user_id = indices(annotations);
				}
				break;
			}
			default: { //For ?categories=Art,Food%20%26%20Drink - explicit categories
				array cats = yield(get_helix_paginated("https://api.twitch.tv/helix/games", (["name": req->variables->categories / ","])));
				if (sizeof(cats)) {
					args->game_id = (array(string))cats->id;
					title = cats->name * ", " + " streams";
					//Include the box art. What should we do with those that don't have any?
					title += replace(sprintf("%{ ![](%s)%}", cats->box_art_url), (["{width}": "20", "{height}": "27"]));
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
					//If ever Twitch reimplements this functionality in Helix, add something
					//like this here:
					//cats = yield(twitch_api_request("........."));
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
		users = yield(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": ids])));
	}
	else {
		if (mapping resp = ensure_login(req, "user:read:follows")) return resp;
		if (mixed ex = catch {
			follows_helix = yield(get_helix_paginated("https://api.twitch.tv/helix/streams/followed",
				(["user_id": (string)req->misc->session->user->id]),
				(["Authorization": "Bearer " + req->misc->session->token])));
		}) {
			//Seems to be a problem fetching, possibly an auth issue.
			//TODO: Check the exact failure and only do this on 401 response
			//Should this happen globally? If any 401 leaks out, log the user out?
			//Or at least, if a 401 leaks out (or if ANY exception leaks), offer a
			//logout link?
			werror("RAIDFINDER: Failed to fetch, revoking login\n");
			werror("%s\n", describe_backtrace(ex));
			m_delete(G->G->http_sessions, req->misc->session->cookie);
			req->misc->session = ([]);
			werror("RAIDFINDER: Returning login page\n");
			return ensure_login(req, "user:read:follows");
		}
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
	mapping(string:int) lc_tag_prefs = mkmapping(lower_case(indices(tag_prefs)[*]), values(tag_prefs));
	mapping cached_status = persist_status->path("raidfinder_cache");
	multiset seen = (<>);
	foreach (follows_helix; int i; mapping strm)
	{
		//Optional filter: Only those that include a stream title hashtag
		//Note that this is a naive case-insensitive prefix search; "hashtag=art" will match "#Artist".
		//(Would it be worth lifting the EU4Parser "fold to ASCII" search?)
		if (req->variables->hashtag) {
			if (!has_value(lower_case(strm->title), "#" + req->variables->hashtag)) {follows_helix[i] = 0; continue;}
			//TODO: Put a highlight on the search term???
		}
		mapping(string:int) recommend = ([]);
		foreach (strm->tags || ({ }), string tag)
			if (int pref = lc_tag_prefs[lower_case(tag)]) recommend["Tag prefs"] += PREFERENCE_MAGIC_SCORES[pref];
		strm->category = G->G->category_names[strm->game_id] || strm->game_name;
		if (mapping st = cached_status[strm->user_id]) strm->chanstatus = st;
		int otheruid = (int)strm->user_id;
		if (otheruid == userid) {follows_helix[i] = 0; continue;} //Exclude self. There's no easy way to know if you should have shown up, so just always exclude.
		if (seen[otheruid]) {follows_helix[i] = 0; continue;} //Duplicate results sometimes happen across pagination. Suppress them. (We may have lost something in the gap but we can't know.)
		seen[otheruid] = 1;
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
		strm->raids = ({ });
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
			"logged_in_as": (int)logged_in->?id,
			"on_behalf_of_userid": userid, //The same userid as you're logged in as, unless for= is specified
			"follows": follows_helix,
			"all_tags": ({ }), //Deprecated as of 20230127 - tags by ID are no longer a thing.
			"your_stream": your_stream, "highlights": highlights,
			"tag_prefs": tag_prefs, "lc_tag_prefs": lc_tag_prefs,
			"MAX_PREF": MAX_PREF, "MIN_PREF": MIN_PREF,
			"all_raids": all_raids[<99..], "mode": "normal",
			"annotations": annotations,
			"render_time": (string)tm->get(),
			"raid_suggestions": userid && (int)logged_in->?id == userid ? prune_raid_suggestions(logged_in->id) : ({ }),
		]),
		"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
		"title": title,
		"raidbtn": raidbtn,
		"backlink": "<a href=\"raidfinder?menu\">Other raid finder modes</a>",
	]));
}

//Record what the client is interested in hearing about. It's not consistent or coherent
//enough to use the standard 'groups' system, as a single client may be interested in
//many similar things, but it's the same kind of idea.
void websocket_cmd_interested(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (mappingp(msg->want_streaminfo)) conn->want_streaminfo = msg->want_streaminfo;
}

@retain: mapping raids_in_progress = ([]);
constant messagetypes = ({"USERNOTICE"});
void irc_message(string type, string chan, string msg, mapping attrs) {
	if (attrs->msg_id == "raid") {
		array info = m_delete(raids_in_progress, attrs->user_id);
		if (info[?0] == chan) {
			//This is the raid we were expecting to happen. (Note that any OTHER
			//raids that the target receives while we're busily raiding will come
			//through to this function, but info will be null.)
			if (info[2]->sock) info[2]->sock->send_text(Standards.JSON.encode((["cmd": "update", "raidstatus": "Raid successful!"]), 4));
		}
		if (!sizeof(raids_in_progress) && sizeof(connection_cache)) //If we're connected and don't need to be...
			values(connection_cache)[0]->quit(); //... disconnect.
	}
}

continue Concurrent.Future send_raid(string id, int target, mapping conn) {
	mapping result = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?from_broadcaster_id=%s&to_broadcaster_id=%d",
			id, target),
		(["Authorization": "Bearer " + conn->session->token]),
		(["method": "POST", "return_errors": 1]),
	));
	if (result->error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "update", "raidstatus": "Raid failed.", "detail": result->message]), 4));
		return 0;
	}
	conn->sock->send_text(Standards.JSON.encode((["cmd": "update", "raidstatus": "RAIDING!"]), 4));
	//Should there be an "Abort Raid" button on the dialog? The permission required is the same.
	//The biggest problem is that it would be easy to misclick it.
	int cookie = time();
	raids_in_progress[id] = ({"#" + yield(get_user_info(target))->login, cookie, conn});
	//Invert the mapping to deduplicate raid targets
	mapping invert = mkmapping(values(raids_in_progress)[*][0], indices(raids_in_progress));
	object irc = yield(irc_connect(([
		"capabilities": ({"commands", "tags"}),
		"join": indices(invert),
	])));
	mixed _ = yield(task_sleep(120));
	if (raids_in_progress[id][?1] == cookie) {
		//Two minutes after starting the raid, it hasn't gone through. It probably won't.
		m_delete(raids_in_progress, id);
		if (!sizeof(raids_in_progress)) irc->quit();
	}
}

//Note that the front end won't send this message if you're doing a for= raidfind, but
//if you fiddle around and force the message to be sent, all that will happen is that
//the raid is started for YOUR channel, not the one you're raidfinding for.
void websocket_cmd_raidnow(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	multiset havescopes = conn->session->?scopes || (<>);
	if (!havescopes["channel:manage:raids"]) return;
	string id = conn->session->?user->?id; if (!id) return;
	int target = (int)msg->target; if (!target) return; //Ensure that it casts to int correctly
	spawn_task(send_raid(id, target, conn));
}

//Conversely, THIS message is ONLY sent when you're doing a for= raidfind. It includes
//all the necessary information (apart from your identity) for a proper suggestion.
//Again, if you fiddle around and send it manually, it'll be equivalent to any other
//suggestion, but you have to use userids. It might be nice to suppress the Suggest
//button if it would be rejected here, though.
void websocket_cmd_suggestraid(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	int from = (int)conn->session->?user->?id; if (!from) return;
	int target = (int)msg->target; if (!target) return; //Ensure that it casts to int correctly
	int recip = (int)msg["for"]; if (!recip) return;
	mapping notes = persist_status->has_path("raidnotes", (string)recip);
	if (notes->?tags[?"<raidsuggestions>"] < 0) return; //Raid suggestions are disabled, ignore them.
	spawn_task(suggestraid(from, target, recip));
}
continue Concurrent.Future|string suggestraid(int from, int target, int recip) {
	array streams = yield(twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + target))->data;
	if (!sizeof(streams)) return "Stream not live";
	mapping strm = streams[0];
	int userid = recip;
	array users = yield(twitch_api_request("https://api.twitch.tv/helix/users?id=" + target + "&id=" + from))->data;
	mapping target_user, suggestor_user;
	foreach (users, mapping user) {
		//Note that if you suggest yourself as a raid target, that's legit (if a bit lame)
		if (user->id == (string)target) target_user = user;
		if (user->id == (string)from) suggestor_user = user;
	}
	if (!target_user || !suggestor_user) return "Unable to get user/channel details"; //Shouldn't normally happen - might be if weird stuff breaks though
	//TODO: Deduplicate with the main work
	strm->category = G->G->category_names[strm->game_id] || strm->game_name;
	//If we can't pull up the chanstatus from cache, populate it with the one most interesting part.
	if (mapping st = persist_status->path("raidfinder_cache")[strm->user_id]) strm->chanstatus = st;
	else {
		mapping settings = yield(twitch_api_request("https://api.twitch.tv/helix/chat/settings?broadcaster_id=" + target));
		if (arrayp(settings->data) && sizeof(settings->data)) strm->chanstatus = (["cache_time": time(), "chat_settings": settings->data[0]]);
	}
	int otheruid = (int)strm->user_id;
	strm->broadcaster_type = target_user->broadcaster_type;
	strm->profile_image_url = target_user->profile_image_url;
	mapping notes = persist_status->has_path("raidnotes", (string)userid) || ([]);
	if (string n = notes[(string)otheruid]) strm->notes = n;
	if (!strm->url) strm->url = "https://twitch.tv/" + strm->user_login; //Is this always correct?
	int swap = otheruid < userid;
	array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[(string)(swap ? userid : otheruid)];
	int recent = time() - 86400 * 30;
	int ancient = time() - 86400 * 365;
	strm->raids = ({ });
	foreach (raids || ({ }), mapping raid) //Note that these may not be sorted correctly. Should we sort explicitly?
	{
		object time = Calendar.ISO.Second("unix", raid->time);
		strm->raids += ({sprintf("%s%s %s raided %s",
			swap != raid->outgoing ? ">" : "<",
			time->format_ymd(), raid->from, raid->to,
		)});
		if (!undefinedp(raid->viewers) && raid->viewers != -1)
			strm->raids[-1] += " with " + raid->viewers;
	}
	sort(lambda(string x) {return x[1..];}(strm->raids[*]), strm->raids); //Sort by date, ignoring the </> direction marker
	strm->raids = Array.uniq2(strm->raids);
	//TODO: See if this was suggested by a mod or VIP.
	strm->suggested_by = suggestor_user;
	strm->suggested_at = time();
	raid_suggestions[(string)recip] += ({strm});
	string sendme = Standards.JSON.encode((["cmd": "update", "suggestions": prune_raid_suggestions((string)recip)]));
	foreach (websocket_groups[""], object sock) if (sock && sock->state == 1) {
		mapping c;
		if (catch {c = sock->query_id();}) continue; //If older Pike, suggestions won't work.
		if ((int)c->session->?user->?id == recip) sock->send_text(sendme);
	}
}

constant builtin_description = "Send a raid suggestion";
constant builtin_name = "Raid suggestion";
constant builtin_param = ({"Suggestion"});
constant vars_provided = ([
	"{error}": "Normally blank, but can have an error message",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string|array param) {
	if (arrayp(param)) param = param[0];
	//No facility currently for sending comments about the suggestion, but you can include
	//them and we'll ignore them (they'll be in chat anyway)
	sscanf(param, "%*stwitch.tv/%[^ ]", param);
	int target;
	if (catch (target = yield(get_user_id(param)))) return (["{error}": "Unknown channel name"]);
	string error;
	if (mixed ex = catch {error = yield(suggestraid(person->uid, target, channel->userid));})
		return (["{error}": describe_error(ex)]);
	return (["{error}": error || ""]);
}

protected void create(string name) {
	::create(name);
	//Clean out the raid finder cache of anything more than two weeks old
	mapping cache = persist_status["raidfinder_cache"] || ([]);
	int stale = time() - 86400 * 14;
	foreach (indices(cache), string uid) {
		if (cache[uid]->cache_time < stale) m_delete(cache, uid);
	}
	persist_status->save();
}
