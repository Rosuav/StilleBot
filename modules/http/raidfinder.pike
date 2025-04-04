#charset utf-8
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

multiset(string) creative_names = (<
	"Art", "Software and Game Development", "Food & Drink", "Music", "DJs",
	"Makers & Crafting", "Miniatures & Models", "Writing & Reading",
	"Lego & Brickbuilding",
	"Beauty & Body Art", //Is this still a thing? Not seeing it, maybe got folded back into Art.
>);
multiset(int) creatives = (<>);
@retain: mapping raid_suggestions = ([]);
@retain: mapping raidfinder_cache = ([]);

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
* [Categories you follow](raidfinder?categories) - everyone who's currently
  online in any of the categories you follow. Note that Twitch's own list of your
  followed channels is currently independent from channels followed on this tool.
* <form><label>Explore a stream team: <input name=team size=20></label> <input type=submit value=View></form>
  Show any stream team by name (look in the URL - not always the same as the display).
* [Pixel Plush users](raidfinder?categories=pixelplush) - everyone who's currently
  using games from [Pixel Plush](https://pixelplush.dev). The same channels as are
  seen on their homepage carousel. No login required.
* [Mustard Mine users](raidfinder?categories=mustardmine) - those channels for which
  the bot is active. Requires no login.
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

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req)
{
	System.Timer tm = System.Timer();
	//Try to find all creative categories and get their IDs. Is there a better way to do this?
	if (sizeof(creatives) < sizeof(creative_names)) {
		//If any aren't found, we'll scan this list repeatedly every time a page is loaded.
		foreach (G->G->category_names; int id; string name)
			if (creative_names[name]) creatives[id] = 1;
	}
	if (req->request_type == "POST") return jsonify((["error": "Switch to WS message pls"])) | (["error": 429]);
	mapping logged_in = req->misc->session && req->misc->session->user;
	if (req->variables->streamlength) return jsonify((["error": "Switch to ws message pls"])) | (["error": 429]);
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
			if (sizeof(online) == 1) return redirect("/raidfinder?for=" + online[0]); //Send you straight there if only one (uses the ID for simplicity)
			array lines = ({ });
			foreach (sort(online), int id) {
				object chan = G->G->irc->id[id];
				if (chan) lines += ({sprintf("<li><a href=\"/raidfinder?for=%s\">%s</a></li>",
					chan->config->login, chan->config->display_name,
				)});
			}
			return (["data": "<style>body{font-size:16pt}</style><ul>" + lines * "\n" + "</ul><p>See tiled: <a href=\"raidfinder?categories=mustardmine\">categories=mustardmine</a></p>", "type": "text/html"]);
		}
		if (chan == "!demo") return redirect("raidfinder?categories=mustardmine");
		if (chan == (string)(int)chan) userid = (int)chan;
		else userid = await(get_user_id(chan));
	}
	else if (logged_in) userid = (int)logged_in->id; //Raidfind for self if logged in.
	//TODO: Based on the for= or the logged in user, determine whether raids are tracked.
	array follows_helix;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for=
	//annotation. For notes attached to a channel, that channel's ID is
	//used; other forms of notes are attached to specific keywords. In a
	//previous iteration of this, notes ID 0 was used for "highlight".
	mapping notes = await(G->G->DB->load_config(logged_in->?id, "raidnotes"));
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
		array f = await(get_helix_paginated("https://api.twitch.tv/helix/channels/followed",
				(["user_id": (string)req->misc->session->user->id]),
				(["Authorization": "Bearer " + req->misc->session->token])));
		follows_helix = await(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": f->broadcaster_id])));
		array users = await(get_users_info(highlightids));
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
			"title": "All follows (" + sizeof(follows_helix) + ")",
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
	array users;
	if (catch {users = await(get_users_info(highlightids));}) {
		//Some or all of the users don't exist. Assume that any that DO exist are now in
		//the cache, and prune the rest. TODO: Ensure that this is actually the cause of
		//the error (might need some support inside poll.pike).
		users = G->G->user_info[highlightids[*]] - ({0});
	}
	highlights = users->login * "\n";
	string title = "Followed streams", auxtitle = "", catfollow = "";
	//Special searches, which don't use your follow list (and may be possible without logging in)
	if (req->variables->login == "demo") return redirect("raidfinder?categories=mustardmine"); //Old URL for the same functionality
	if (req->variables->raiders || req->variables->categories || req->variables->login || req->variables->train || req->variables->highlights || req->variables->team) {
		mapping args = ([]);
		if (req->variables->raiders) {
			//Raiders mode (categories omitted but "?raiders" specified). Particularly useful with a for= search.
			//List everyone who's raided you, including their timestamps
			//Assume that the last entry in each array is the latest.
			//The result is that raiders will contain one entry for each
			//unique user ID that has ever raided in, and raidtimes will
			//have the corresponding timestamps.
			array raids = await(G->G->DB->load_raids(0, userid));
			array raiders = ({ }), raidtimes = ({ });
			foreach (raids, mapping r) {
				raiders += ({(string)r->fromid});
				raidtimes += ({r->data[-1]->timestamp});
			}
			sort(raidtimes, raiders);
			args->user_id = raiders[<99..]; //Is it worth trying to support more than 100 raiders? Would need to paginate.
		}
		else if (req->variables->highlights) {
			//Restrict your follow list to those you have highlighted.
			args->user_id = (array(string))highlightids;
			title = "Highlighted channels";
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
			if (!(int)owner) owner = (string)await(get_user_id(owner));
			mapping trncfg = await(G->G->DB->load_config(owner, "raidtrain"))->cfg;
			array casters = trncfg->?all_casters;
			if (!casters) return "No such raid train - check the link and try again";
			args->user_id = (array(string))casters;
			title = "Raid Train: " + (trncfg->title || "(untitled)");
		}
		else if (string|array team = req->variables->team) {
			//Team may be an array (team=X&team=Y), a comma-separated list (team=X,Y - also
			//the obvious form team=X counts as this), or blank (team=) meaning "my teams".
			if (team == "") {
				if (mapping resp = ensure_login(req)) return resp;
				team = await(twitch_api_request("https://api.twitch.tv/helix/teams/channel?broadcaster_id=" + userid))->data->team_name || ({ });
			}
			else if (stringp(team)) team /= ",";
			//team should now be an array of team names, regardless of how it was input
			args->user_id = ({ });
			array team_display_names = ({ });
			foreach (team; int i; string t) catch {
				mixed data = await(twitch_api_request("https://api.twitch.tv/helix/teams?name=" + t))->data; //what if team name has specials?
				if (!sizeof(data)) continue; //Probably team not found
				team_display_names += ({data[0]->team_display_name});
				args->user_id += data[0]->users->user_id;
			};
			if (!sizeof(args->user_id)) title = "Stream Team not found"; //Most likely this is because you misspelled the team name
			else if (sizeof(team_display_names) > 1) title = "Stream Teams: " + team_display_names * ", ";
			else title = "Stream Team: " + team_display_names[0];
		}
		else if (mapping tradingcards = req->variables->categories && await(G->G->DB->load_config(0, "tradingcards"))->collections[lower_case(req->variables->categories)]) {
			//categories=Canadian to see who's live from the Canadian Streamers collection of trading cards
			title = "Active " + tradingcards->label + " streamers";
			args->user_id = tradingcards->streamers;
		}
		else switch (req->variables->categories) {
			case "mustardmine":
				args->user_id = (array(string))(indices(G->G->irc->id) - ({0}));
				title = "Mustard Mine users";
				auxtitle = " <img src=/static/MustardMineAvatar.png style=\"height: 1.25em\">";
				break;
			case "pixelplush": { //categories=pixelplush - use an undocumented API to find people playing the !drop game etc
				object res = await(Protocols.HTTP.Promise.get_url(
					"https://api.pixelplush.dev/v1/analytics/sessions/live"
				));
				mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
				if (!arrayp(data)) title = "Unable to fetch";
				else {
					title = "Active Pixel Plush streamers";
					foreach (data, mapping strm)
						if (strm->platform == "twitch") annotations[strm->stream->userId] += ({strm->theme});
					foreach (annotations; string uid; array anno)
						annotations[uid] = Array.uniq(anno);
					args->user_id = indices(annotations);
				}
				break;
			}
			default: { //For ?categories=Art,Food%20%26%20Drink - explicit categories
				array cats = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["name": req->variables->categories / ","])));
				if (sizeof(cats)) {
					args->game_id = (array(string))cats->id;
					title = cats->name * ", " + " streams";
					//Include the box art. What should we do with those that don't have any?
					auxtitle = replace(sprintf("%{ ![](%s)%}", cats->box_art_url), (["{width}": "20", "{height}": "27"]));
					if (req->misc->session->user) {
						string follow = "unfollow>💔 Unfollow";
						array followed = await(G->G->DB->load_config(req->misc->session->user->id, "followed_categories", ({ })));
						if (sizeof(followed & cats->id) < sizeof(cats->id))
							follow = "follow>💜 Follow"; //You aren't following them all, so offer "Follow" rather than "Unfollow"
						string catdesc = " these categories";
						if (sizeof(cats) == 1) catdesc = " '" + cats[0]->name + "'";
						catfollow = "<button id=followcategory data-cats=\"" + cats->id * "," + "\" data-action=" + follow + catdesc + "</button><br>";
					}
					break;
				}
				//Else fall through. Any sort of junk category name, treat it as if it's "?categories"
			}
			case "": case "categories": { //For ?categories and ?categories= modes, show those you follow
				if (mapping resp = ensure_login(req)) return resp;
				args->game_id = await(G->G->DB->load_config(req->misc->session->user->id, "followed_categories", ({ })));
				title = "Followed categories";
				catfollow = "<button id=followcategory data-action=show data-cats=\"" + args->game_id * "," + "\">💜 All followed categories</button><br>";
				break;
			}
		}
		[array streams, mapping self] = await(Concurrent.all(
			get_helix_paginated("https://api.twitch.tv/helix/streams", args),
			twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + userid),
		));
		array(string) ids = streams->user_id + ({(string)userid});
		follows_helix = streams + self->data;
		users = await(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": ids])));
	}
	else {
		if (mapping resp = ensure_login(req, "user:read:follows")) return resp;
		if (mixed ex = catch {
			follows_helix = await(get_helix_paginated("https://api.twitch.tv/helix/streams/followed",
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
			req->misc->session = (["hacky": "hack"]); //Ensure that a new session is created
			werror("RAIDFINDER: Returning login page\n");
			return ensure_login(req, "user:read:follows");
		}
		//Ensure that we have the user we're looking up (yourself, unless it's a for=USERNAME raidfind)
		follows_helix += await(get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": (string)userid])));
		//Grab some additional info from the Users API, including profile image and
		//whether the person is partnered or affiliated.
		users = await(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": follows_helix->user_id + ({(string)userid})])));
	}
	mapping your_stream;
	foreach (follows_helix, mapping strm)
		if ((int)strm->user_id == userid) your_stream = strm;
	mapping(int:mapping(string:mixed)) extra_info = ([]);
	//Get some extra info that isn't in the /streams API.
	if (sizeof(follows_helix)) {
		array channels = await(get_helix_paginated("https://api.twitch.tv/helix/channels", (["broadcaster_id": follows_helix->user_id])));
		foreach (channels, mapping chan)
			extra_info[(int)chan->broadcaster_id] = ([
				"is_branded_content": chan->is_branded_content,
				"content_classification_labels": chan->content_classification_labels,
			]);
	}
	foreach (users, mapping user)
		extra_info[(int)user->id] = ([
			"broadcaster_type": user->broadcaster_type,
			"profile_image_url": user->profile_image_url,
		]) | (extra_info[(int)user->id] || ([]));
	//Okay! Preliminaries done. Let's look through the Helix-provided info and
	//build up a final result.
	mapping(string:int) tag_prefs = notes->tags || ([]);
	mapping(string:int) lc_tag_prefs = mkmapping(lower_case(indices(tag_prefs)[*]), values(tag_prefs));
	multiset seen = (<>);
	foreach (follows_helix; int i; mapping strm)
	{
		//Optional filter: Only those that include a stream title hashtag
		//Note that this is a naive case-insensitive prefix search; "hashtag=art" will match "#Artist".
		//(Would it be worth lifting the EU4Parser "fold to ASCII" search?)
		if (req->variables->hashtag) {
			if (!has_value(lower_case(strm->title), "#" + lower_case(req->variables->hashtag))
				&& !has_value(lower_case((strm->tags || ({ }))[*]), lower_case(req->variables->hashtag)))
					{follows_helix[i] = 0; continue;}
			//TODO: Put a highlight on the search term???
		}
		mapping(string:int) recommend = ([]);
		foreach (strm->tags || ({ }), string tag)
			if (int pref = lc_tag_prefs[lower_case(tag)]) recommend["Tag prefs"] += PREFERENCE_MAGIC_SCORES[pref];
		strm->category = G->G->category_names[strm->game_id] || strm->game_name;
		if (mapping st = get_cache_chanstatus(strm->user_id, userid)) strm->chanstatus = st;
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
		//Would be nice to optimize this. Currently it's a separate database query for each streamer.
		array raids = await(G->G->DB->load_raids(userid, otheruid, 1));
		int recent = time() - 86400 * 30;
		int ancient = time() - 86400 * 365;
		float raidscore = 0.0;
		int have_recent_outgoing = 0, have_old_incoming = 0;
		strm->raids = ({ });
		foreach (raids, mapping raidset) foreach (raidset->data, mapping raid)
		{
			//write("DEBUG RAID LOG: %O\n", raid);
			//TODO: Translate these by timezone (if available)
			object time = Calendar.ISO.Second("unix", raid->time);
			raidscore *= 0.85; //If there are tons of raids, factor the most recent ones strongly, and weaken it into the past.
			if (raidset->fromid == (int)userid) {
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
	array raidraw = await(G->G->DB->load_raids(userid, 0, 1));
	foreach (raidraw, mapping raidset) {
		if (raidset->fromid == (int)userid) {
			foreach (raidset->data, mapping raid)
				all_raids += ({raid | (["outgoing": 1])});
		} else all_raids += raidset->data;
	}
	sort(all_raids->time, all_raids);
	follows_helix -= ({0}); //Remove self (already nulled out)
	sort(-follows_helix->recommend[*], follows_helix); //Sort by magic initially
	if (!G->G->ccl_options_table) {
		//Assume CCLs seldom change. Currently no cache purge option.
		array ccls = await(twitch_api_request("https://api.twitch.tv/helix/content_classification_labels"))->data;
		G->G->ccl_names = mkmapping(ccls->id, ccls->name);
		G->G->ccl_options_table = sprintf("> %s | <input type=radio name=CCL_%s value=0> | <input type=radio name=CCL_%<s value=-1> | <input type=radio name=CCL_%<s value=-2> | <input type=radio name=CCL_%<s value=-3>\n", ccls->name[*], ccls->id[*]) * "";
	}
	return render(req, ([
		"vars": ([
			"ws_group": "",
			"logged_in_as": (int)logged_in->?id,
			"on_behalf_of_userid": userid, //The same userid as you're logged in as, unless for= is specified
			"follows": follows_helix,
			"your_stream": your_stream, "highlights": highlights,
			"tag_prefs": tag_prefs, "lc_tag_prefs": lc_tag_prefs,
			"MAX_PREF": MAX_PREF, "MIN_PREF": MIN_PREF,
			"ccl_names": G->G->ccl_names,
			"all_raids": all_raids[<99..], "mode": "normal",
			"annotations": annotations,
			"render_time": (string)tm->get(),
			"raid_suggestions": userid && (int)logged_in->?id == userid ? prune_raid_suggestions(logged_in->id) : ({ }),
		]),
		"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
		"title": title, "auxtitle": auxtitle, "catfollow": catfollow,
		"raidbtn": raidbtn,
		"backlink": "<a href=\"raidfinder?menu\">Other raid finder modes</a>",
		"ccl_options": G->G->ccl_options_table,
	]));
}

__async__ mapping websocket_cmd_update_tagpref(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Update tag preferences. Note that this does NOT fully replace
	//existing tag prefs; it changes only those which are listed.
	//Note also that tag prefs, unlike other raid notes, are stored
	//as a mapping. (Should they be stored separately?)
	mapping notes = await(G->G->DB->mutate_config(conn->session->user->id, "raidnotes") {
		mapping tags = __ARGS__[0]->tags;
		if (!tags) tags = __ARGS__[0]->tags = ([]);
		string id = msg->tag; int pref = msg->pref;
		//Hack: "<viewership>" is used for the "hide viewer counts" setting (boolean).
		//And "<CCL*>" is used for CCL settings, which store -3 to 0.
		if (id != "" && id[0] == '<' && !has_prefix(id, "<CCL")) pref = pref < 0 ? -1 : 0;
		if (!pref || pref > MAX_PREF || pref < MIN_PREF) m_delete(tags, id);
		else tags[id] = pref;
	});
	return (["cmd": "tagprefs", "prefs": notes->tags]);
}

__async__ void websocket_cmd_update_highlights(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Channel names are separated by space or newline or comma or whatever
	array(string) channels = replace(msg->highlights || "", ",;\n"/"", " ") / " " - ({""});
	//Trim URLs down to just the channel name
	foreach (channels; int i; string c) sscanf(c, "http%*[s]://twitch.tv/%s%*[?/]", channels[i]);
	array users = await(get_users_info(channels, "login")); //TODO: If this throws "user not found", report it nicely
	await(G->G->DB->mutate_config(conn->session->user->id, "raidnotes") {
		__ARGS__[0]->highlight = (array(string))users->id * "\n";
	});
	conn->sock->send_text(Standards.JSON.encode(([
		"cmd": "highlights",
		"highlights": users->login * "\n",
		"highlightids": users->id,
	]), 4));
}

__async__ void websocket_cmd_update_notes(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!intp(msg->id)) return;
	string newnotes = msg->notes || "";
	mapping notes = await(G->G->DB->load_config(conn->session->user->id, "raidnotes"));
	if (newnotes == "") m_delete(notes, (string)msg->id);
	else notes[(string)msg->id] = newnotes;
	await(G->G->DB->save_config(conn->session->user->id, "raidnotes", notes));
}

__async__ mapping followcategory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!arrayp(msg->cats) || !sizeof(msg->cats)) return 0; //No cats, nothing to do.
	switch (msg->action) {
		case "query": {
			array cats = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["id": msg->cats])));
			return (["cats": cats]);
		}
		case "follow": case "unfollow": {
			string uid = conn->session->user->?id;
			if (!(int)uid) return 0; //Not logged in, no following/unfollowing possible
			array cats = await(G->G->DB->load_config(uid, "followed_categories", ({ })));
			if (msg->action == "follow") cats += msg->cats;
			else cats -= msg->cats;
			G->G->DB->save_config(uid, "followed_categories", cats);
			return (["status": msg->action == "follow" ? "Now following 💜" : "No longer following 💔"]);
		}
		default: break;
	}
}
void websocket_cmd_followcategory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	followcategory(conn, msg)->then() {
		if (__ARGS__[0]) conn->sock->send_text(Standards.JSON.encode((["cmd": "followcategory"]) | __ARGS__[0]));
	};
}

mapping get_cache_chanstatus(string chan, int|void userid) {
	//Get chanstatus if we have it, otherwise 0.
	mapping st = raidfinder_cache[chan];
	if (!st || st->cache_time < time() - 86400 * 14) return 0;
	if (userid && (!st->following || !st->following[(string)userid])) return 0; //Legacy cache entries might not have a following[] mapping
	return st;
}
__async__ mapping cache_chanstatus(string chan, int|multiset(int)|void userids) {
	//Ping Twitch and check if there are any chat restrictions. So far I can't do this in bulk, but
	//it's great to be able to query them this way for the VOD length popup. Note that we're not
	//asking for mod settings here, so non_moderator_chat_delay won't be in the response.
	mapping settings = await(twitch_api_request("https://api.twitch.tv/helix/chat/settings?broadcaster_id=" + chan));
	mapping ret = raidfinder_cache[chan] = (["following": ([])]);
	if (arrayp(settings->data) && sizeof(settings->data)) ret->chat_settings = settings->data[0];

	//Hang onto this info in cache, apart from is_following (below).
	ret->cache_time = time();
	if (intp(userids)) userids = (<userids>);
	userids[0] = userids[(int)chan] = 0; //Remove uninteresting ones
	foreach (userids; int userid;) {
		//Also show whether the target(s) is/are following this stream.
		array creds = token_for_user_id(userid);
		array scopes = creds[1] / " ";
		if (has_value(scopes, "user:read:follows")) {
			mapping info = await(twitch_api_request(sprintf("https://api.twitch.tv/helix/channels/followed?user_id=%d&broadcaster_id=%s", userid, chan),
				(["Authorization": "Bearer " + creds[0]])));
			if (sizeof(info->data)) {
				mapping f = ret->following[(string)userid] = info->data[0];
				object howlong = time_from_iso(f->followed_at)->distance(Calendar.ISO.now());
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
				f->follow_length = length;
				f->from_name = await(get_user_info(userid))->display_name;
			}
			else ret->following[(string)userid] = ([]);
		}
	}
	//Publish this info to all socket-connected clients that care.
	string sendme = Standards.JSON.encode((["cmd": "chanstatus", "channelid": chan, "chanstatus": ret]));
	foreach (websocket_groups[""] || ({ }), object sock) if (sock && sock->state == 1) {
		//See if the client is interested in this channel
		mapping conn = sock->query_id();
		if (!multisetp(conn->want_streaminfo) || !conn->want_streaminfo[chan]) continue;
		conn->want_streaminfo[chan] = 0;
		sock->send_text(sendme);
	}
	return ret;
}

void precache_chanstatus() {
	m_delete(G->G, "raidfinder_precache_timer");
	mapping(string:multiset) all_wanted = ([]);
	foreach (websocket_groups[""] || ({ }), object sock) if (sock && sock->state == 1) {
		//See if the client is interested in this channel
		mapping conn = sock->query_id();
		if (multisetp(conn->want_streaminfo))
			foreach (conn->want_streaminfo; string id;)
				all_wanted[id] |= (<conn->on_behalf_of_userid>);
	}
	if (!sizeof(all_wanted)) return;
	cache_chanstatus(@random(all_wanted)); //TODO: List the for= for each requestor
	G->G->raidfinder_precache_timer = call_out(G->G->websocket_types->raidfinder->precache_chanstatus, 1);
}

//Record what the client is interested in hearing about. It's not consistent or coherent
//enough to use the standard 'groups' system, as a single client may be interested in
//many similar things, but it's the same kind of idea.
void websocket_cmd_interested(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!arrayp(msg->want_streaminfo)) return;
	conn->want_streaminfo = (multiset)msg->want_streaminfo;
	conn->on_behalf_of_userid = (int)msg->on_behalf_of_userid;
	if (!G->G->raidfinder_precache_timer) G->G->raidfinder_precache_timer = call_out(precache_chanstatus, 1);
}

__async__ void websocket_cmd_streamlength(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Provide some info on VOD durations for the front end to display graphically
	//Additionally (since this is a costly check anyway, so it won't add much), it
	//checks if the for= target is following them.
	string chan = msg->userid;
	array vods = await(get_helix_paginated("https://api.twitch.tv/helix/videos", (["user_id": chan, "type": "archive"])));
	if (string ignore = msg->ignore) //Ignore the stream ID for a currently live broadcast
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

	mapping chanstatus = await(cache_chanstatus(chan, msg["for"]));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "streamlength"]) | ret | chanstatus));
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

__async__ void send_raid(string id, int target, mapping conn) {
	mapping result = await(twitch_api_request(sprintf(
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
	raids_in_progress[id] = ({"#" + await(get_user_info(target))->login, cookie, conn});
	//Invert the mapping to deduplicate raid targets
	mapping invert = mkmapping(values(raids_in_progress)[*][0], indices(raids_in_progress));
	object irc = await(irc_connect(([
		"capabilities": ({"commands", "tags"}),
		"join": indices(invert),
	])));
	await(task_sleep(120));
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
	suggestraid(from, target, recip);
}
__async__ string suggestraid(int from, int target, int recip) {
	mapping notes = await(G->G->DB->load_config(recip, "raidnotes"));
	if (notes->?tags[?"<raidsuggestions>"] < 0) return "Streamer does not accept suggestions";
	array streams = await(twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + target))->data;
	if (!sizeof(streams)) return "Stream not live";
	mapping strm = streams[0];
	int userid = recip;
	array users = await(twitch_api_request("https://api.twitch.tv/helix/users?id=" + target + "&id=" + from))->data;
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
	strm->chanstatus = await(cache_chanstatus(strm->user_id, recip));
	int otheruid = (int)strm->user_id;
	strm->broadcaster_type = target_user->broadcaster_type;
	strm->profile_image_url = target_user->profile_image_url;
	if (string n = notes[(string)otheruid]) strm->notes = n;
	if (!strm->url) strm->url = "https://twitch.tv/" + strm->user_login; //Is this always correct?
	array raids = await(G->G->DB->load_raids(userid, otheruid, 1));
	int recent = time() - 86400 * 30;
	int ancient = time() - 86400 * 365;
	strm->raids = ({ });
	foreach (raids, mapping raidset) foreach (raidset->data, mapping raid)
	{
		object time = Calendar.ISO.Second("unix", raid->time);
		strm->raids += ({sprintf("%s%s %s raided %s",
			raidset->fromid == (int)userid ? ">" : "<",
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
	G->G->DB->mutate_config(recip, "raid_suggestions") {__ARGS__[0]->history += ({([
		"suggestor": from, "target": target, "time": time(),
	])});};
	string sendme = Standards.JSON.encode((["cmd": "update", "suggestions": prune_raid_suggestions((string)recip)]));
	foreach (websocket_groups[""], object sock) if (sock && sock->state == 1) {
		mapping c;
		if (catch {c = sock->query_id();}) continue; //If older Pike, suggestions won't work.
		if ((int)c->session->?user->?id == recip) sock->send_text(sendme);
	}
}

constant builtin_description = "Send a raid suggestion";
constant builtin_name = "Raid suggestion";
constant builtin_param = ({"Suggestion"}); //Maybe add "Comments" as second param?
constant vars_provided = ([]);

__async__ mapping message_params(object channel, mapping person, array params, mapping cfg) {
	if (cfg->simulate) return ([]);
	//No facility currently for sending comments about the suggestion, but you can include
	//them and we'll ignore them (they'll be in chat anyway)
	string chan = params[0];
	sscanf(chan, "%*stwitch.tv/%[^ ]", chan);
	sscanf(chan, "%*[@]%[^ ]", chan);
	int target;
	if (catch (target = await(get_user_id(chan)))) error("Unknown channel name\n");
	if (!target) error("Unknown channel name\n");
	string err = await(suggestraid(person->uid, target, channel->userid));
	if (err && err != "") error(err + "\n");
}

protected void create(string name) {
	::create(name);
	//Clean out the VOD length cache of anything more than two weeks old
	int stale = time() - 86400 * 14;
	foreach (indices(raidfinder_cache), string uid) {
		if (raidfinder_cache[uid]->cache_time < stale) m_delete(raidfinder_cache, uid);
	}
}
