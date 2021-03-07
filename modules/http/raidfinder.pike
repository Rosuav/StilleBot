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

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
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
			return get_users_info(channels, "login")->then(lambda(array users) {
				notes->highlight = (array(string))users->id * "\n";
				return jsonify(([
					"highlights": users->login * "\n",
					"highlightids": users->id,
				]), 7);
			}, lambda(mixed err) {werror("%O\n", err); return (["error": 500]);}); //TODO: If it's "user not found", report it nicely
		}
		if (newnotes == "") m_delete(notes, (string)body->id);
		else notes[(string)body->id] = newnotes;
		persist_status->save();
		return (["error": 204]);
	}
	Concurrent.Future uid = Concurrent.resolve((int)req->misc->session->user->id);
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
		uid = get_user_id(chan);
	}
	//TODO: Based on the for= or the logged in user, determine whether raids are tracked.
	mapping raids = ([]);
	array follows_kraken, follows_helix;
	mapping(int:mapping(string:mixed)) extra_kraken_info = ([]);
	mapping your_stream;
	int userid;
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
		return get_helix_paginated("https://api.twitch.tv/helix/users/follows",
				(["from_id": (string)req->misc->session->user->id]))
			->then(lambda(array f) {
				array(array(string)) blocks = f->to_id / 100.0;
				return Concurrent.all(twitch_api_request(("https://api.twitch.tv/helix/users?first=100" + sprintf("%{&id=%s%}", blocks[*])[*])[*]));
			})->then(lambda(array f) {
				/*
				Each person looks like this:
				([
					"broadcaster_type": "partner",
					"created_at": "2015-07-16T00:57:30.61026Z",
					"description": "I like cooking.  I like yummy food.  Let me show you how to cook yummy food.",
					"display_name": "CookingForNoobs",
					"id": "96253346",
					"login": "cookingfornoobs",
					"offline_image_url": "https://static-cdn.jtvnw.net/jtv_user_pictures/fe6534bb00bbb4cd-channel_offline_image-1920x1080.jpeg",
					"profile_image_url": "https://static-cdn.jtvnw.net/jtv_user_pictures/54728b80-cd99-4d03-9cfe-44a59152f7a2-profile_image-300x300.jpg",
					"type": "",
					"view_count": 1658855,
				])
				*/
				follows_helix = f->data * ({ });
				return get_users_info(highlightids);
			})->then(lambda(array users) {
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
			}); //TODO as below: Return a nice message if for=junk given
	}
	return uid->then(lambda(int u) {
			userid = u;
			string login = req->misc->session->user->login, disp = req->misc->session->user->display_name;
			if (mapping user = u != (int)req->misc->session->user->id && G->G->user_info[u])
			{
				login = user->login || user->name; //helix || kraken
				disp = user->display_name;
			}
			//Legacy data (currently all data): Parse the outgoing raid log
			//Note that this cannot handle renames, and will 'lose' them.
			//TODO: Show these in the logged-in user's specified timezone (if we have a
			//channel for that user), or UTC. Apologize on the page if no TZ available.
			//TODO: If working on behalf of someone else, which tz should we use?
			foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n", string raid)
			{
				sscanf(raid, "[%d-%d-%d %*d:%*d:%*d] %s => %s", int y, int m, int d, string from, string to);
				if (!to) continue;
				if (y >= 2021) break; //Ignore newer entries and rely on the proper format (when should the cutoff be?)
				if (from == login) raids[lower_case(to)] += ({sprintf(">%d-%02d-%02d %s raided %s", y, m, d, from, to)});
				if (to == disp) raids[from] += ({sprintf("<%d-%02d-%02d %s raided %s", y, m, d, from, to)});
			}
			return get_users_info(highlightids);
		})->then(lambda(array users) {
			highlights = users->login * "\n";
			/*
			https://api.twitch.tv/kraken/users/49497888/follows/games
			https://api.twitch.tv/helix/tags/streams - all tags, to allow filtering
			https://api.twitch.tv/helix/streams?" + sprintf("%{game_id=%d&%}", info->follows->game->_id)
			*/
			//Category search - show all streams in the categories you follow
			if (req->variables->categories) return twitch_api_request("https://api.twitch.tv/kraken/users/" + req->misc->session->user->id + "/follows/games")
				->then(lambda(mapping info) {
					return Concurrent.all(
						get_helix_paginated("https://api.twitch.tv/helix/streams", (["game_id": (array(string))info->follows->game->_id])),
						twitch_api_request("https://api.twitch.tv/helix/streams?user_id=" + userid),
					);
				})->then() {
					[array streams, mapping self] = __ARGS__[0];
					array(string) ids = streams->user_id + ({(string)userid});
					//Map channel list to Kraken so we get both sets of info
					return Concurrent.all(
						twitch_api_request("https://api.twitch.tv/kraken/streams/?channel=" + ids * ",")
							->then(lambda(mapping info) {return info->streams;}),
						Concurrent.resolve(streams + ({self->data[0]})),
						get_helix_paginated("https://api.twitch.tv/helix/users", (["id": ids])),
					);
				};
			else return twitch_api_request("https://api.twitch.tv/kraken/streams/followed?limit=100",
					(["Authorization": "OAuth " + req->misc->session->token])
				)->then(lambda(mapping info) {
					array(int) channels = info->streams->channel->_id;
					channels += ({userid});
					write("Fetching %d streams...\n", sizeof(channels));
					//Map channel list to Helix so we get both sets of info
					return Concurrent.all(
						Concurrent.resolve(info->streams),
						get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": (array(string))channels])),
						//The ONLY thing we need /helix/users for is broadcaster_type, which - for
						//reasons unknown to me - is always blank in the main stream info.
						get_helix_paginated("https://api.twitch.tv/helix/users", (["id": (array(string))channels])),
					);
				});
		})->then(lambda(array results) {
			[follows_kraken, follows_helix, array users] = results;
			//write("Kraken: %O\nHelix: %O\nUsers: %O\n", follows_kraken[..3], follows_helix[..3], users[..3]);
			if (!G->G->tagnames) G->G->tagnames = ([]);
			multiset all_tags = (<>);
			foreach (follows_helix, mapping strm)
			{
				//all_tags |= (tag_ids &~ G->G->tagnames); //sorta kinda
				foreach (strm->tag_ids || ({ }), string tag)
					if (!G->G->tagnames[tag]) all_tags[tag] = 1;
			}
			foreach (follows_kraken, mapping strm)
				extra_kraken_info[strm->channel->_id] = ([
					"profile_image_url": strm->channel->logo,
					"url": strm->channel->url,
					//strm->video_height and strm->average_fps might be of interest
				]);
			foreach (users, mapping user) broadcaster_type[(int)user->id] = user->broadcaster_type;
			if (!sizeof(all_tags)) return Concurrent.resolve(({ }));
			write("Fetching %d tags...\n", sizeof(all_tags));
			return get_helix_paginated("https://api.twitch.tv/helix/tags/streams", (["tag_id": (array)all_tags]));
		})->then(lambda(array alltags) {
			foreach (alltags, mapping tag) G->G->tagnames[tag->tag_id] = tag->localization_names["en-us"];
			foreach (follows_helix; int i; mapping strm)
			{
				array tags = ({ });
				foreach (strm->tag_ids || ({ }), string tagid)
					if (string tagname = G->G->tagnames[tagid]) tags += ({(["id": tagid, "name": tagname])});
				strm->tags = tags;
				strm->category = G->G->category_names[strm->game_id];
				strm->raids = raids[strm->user_login] || ({ });
				int otheruid = (int)strm->user_id;
				if (otheruid == userid) {your_stream = strm; follows_helix[i] = 0; continue;}
				if (mapping k = extra_kraken_info[otheruid]) follows_helix[i] = strm = k | strm;
				if (string t = broadcaster_type[otheruid]) strm->broadcaster_type = t;
				if (string n = notes[(string)otheruid]) strm->notes = n;
				if (has_value(highlightids, otheruid)) strm->highlight = 1;
				int swap = otheruid < userid;
				array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[(string)(swap ? userid : otheruid)];
				int recommend = 0;
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
			//List all recent raids. Actually list ALL raids on the current system.
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
			return render_template("raidfinder.md", ([
				"vars": (["follows": follows_helix, "your_stream": your_stream, "highlights": highlights, "all_raids": all_raids[<99..], "mode": "normal"]),
				"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
			]));
		}); //TODO: Return a nice message if for=junk given
}
