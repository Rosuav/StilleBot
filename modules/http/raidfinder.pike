inherit http_endpoint;
/* Raid target finder
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - There's not going to be any easy UI for it, but it'd be great to have a "raided my friend"
    feature, where we can see any time that X raided Y where Y is one of my friends... hard.
  - Might also be worth showing anyone in the same category you're currently in.
  - Also show your followed categories, if possible. Both these would be shown separately.
  - Undocumented https://api.twitch.tv/kraken/users/<userid>/follows/games
    - Lists followed categories. Format is a bit odd but they do seem to include an _id
      (which corresponds to G->G->category_names).
    - Can then use /helix/streams (#get-streams) with game_id (up to ten of them).
    - Scopes required: probably user_read?
*/

string cached_follows;

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
				notes["0"] = (array(string))users->id * "\n";
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
	if (req->variables->use_cache && cached_follows) return render_template("raidfinder.md", (["follows": cached_follows]));
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
	mapping raids = ([]);
	array follows;
	mapping(int:array(string)) channel_tags = ([]);
	mapping your_stream;
	int userid;
	mapping broadcaster_type = ([]);
	//NOTE: Notes come from your *login* userid, unaffected by any for= annotation.
	mapping notes = persist_status->path("raidnotes")[(string)req->misc->session->user->id];
	array highlightids = ({ });
	if (notes && notes["0"]) highlightids = (array(int))(notes["0"] / "\n");
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
				follows = f->data * ({ });
				return get_users_info(highlightids);
			})->then(lambda(array users) {
				highlights = users->login * "\n";
				foreach (follows; int idx; mapping strm) {
					if (string n = notes && notes[strm->id]) strm->notes = n;
					if (has_value(highlightids, (int)strm->id)) strm->highlight = 1;
					strm->order = idx; //Order they were followed. Effectively the same as array order since we don't get actual data.
					//Make some info available in the same way that it is for the main follow list.
					//This allows the front end to access it identically for convenience.
					strm->channel = ([
						"broadcaster_type": strm->broadcaster_type,
						"logo": strm->profile_image_url,
						"display_name": strm->display_name,
						"_id": (int)strm->id,
					]);
				}
				return render_template("raidfinder.md", ([
					"follows": Standards.JSON.encode(follows, Standards.JSON.ASCII_ONLY),
					"your_stream": "0",
					"highlights": Standards.JSON.encode(highlights, Standards.JSON.ASCII_ONLY),
					"sortorders": ({"Channel Creation", "Follow Date", "Name"}) * "\n* ",
					"mode": "allfollows",
				]));
			}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);}); //TODO as below: Return a nice message if for=junk given
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
			return twitch_api_request("https://api.twitch.tv/kraken/streams/followed?limit=100",
				(["Authorization": "OAuth " + req->misc->session->token]));
		})->then(lambda(mapping info) {
			follows = info->streams;
			//All this work is just to get the stream tags (and some info about your own stream)
			array(int) channels = follows->channel->_id;
			channels += ({userid});
			//TODO: Paginate if >100
			write("Fetching %d streams...\n", sizeof(channels));
			return Concurrent.all(
				twitch_api_request("https://api.twitch.tv/helix/streams?first=100" + sprintf("%{&user_id=%d%}", channels)),
				//The ONLY thing we need /helix/users for is broadcaster_type, which - for
				//reasons unknown to me - is always blank in the main stream info.
				twitch_api_request("https://api.twitch.tv/helix/users?first=100" + sprintf("%{&id=%d%}", channels)),
			);
		})->then(lambda(array results) {
			[mapping info, mapping userinfo] = results;
			if (!G->G->tagnames) G->G->tagnames = ([]);
			multiset all_tags = (<>);
			foreach (info->data, mapping strm)
			{
				channel_tags[(int)strm->user_id] = strm->tag_ids;
				if ((int)strm->user_id == userid)
				{
					//Info about your own stream. Handy but doesn't go in the main display.
					//write("Your tags: %O\n", strm->tag_ids); //Is it worth trying to find people with similar tags?
					your_stream = strm;
					your_stream->category = G->G->category_names[strm->game_id];
					continue;
				}
				//all_tags |= (tag_ids &~ G->G->tagnames); //sorta kinda
				foreach (strm->tag_ids || ({ }), string tag)
					if (!G->G->tagnames[tag]) all_tags[tag] = 1;
			}
			foreach (userinfo->data, mapping user) broadcaster_type[(int)user->id] = user->broadcaster_type;
			if (!sizeof(all_tags)) return Concurrent.resolve((["data": ({ })]));
			//TODO again: Paginate if >100
			write("Fetching %d tags...\n", sizeof(all_tags));
			return twitch_api_request("https://api.twitch.tv/helix/tags/streams?first=100" + sprintf("%{&tag_id=%s%}", (array)all_tags));
		})->then(lambda(mapping info) {
			foreach (info->data, mapping tag) G->G->tagnames[tag->tag_id] = tag->localization_names["en-us"];
			foreach (follows, mapping strm)
			{
				array tags = ({ });
				foreach (channel_tags[strm->channel->_id] || ({ }), string tagid)
					if (string tagname = G->G->tagnames[tagid]) tags += ({(["id": tagid, "name": tagname])});
				strm->tags = tags;
				strm->raids = raids[strm->channel->name] || ({ });
				int otheruid = (int)strm->channel->_id;
				if (string t = broadcaster_type[otheruid]) strm->channel->broadcaster_type = t;
				if (string n = notes && notes[(string)otheruid]) strm->notes = n;
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
						if (raid->time > recent) recommend -= 20;
						else if (raid->time > ancient) recommend -= 5;
					}
					else {
						strm->raids += ({sprintf("<%s %s raided %s", time->format_ymd(), raid->from, raid->to)});
						if (raid->time > recent) recommend += 10;
						else if (raid->time > ancient) recommend += 20;
					}
					if (!undefinedp(raid->viewers) && raid->viewers != -1)
						strm->raids[-1] += " with " + raid->viewers;
				}
				//For some reason, strm->raids[*][1..] doesn't work. ??
				sort(lambda(string x) {return x[1..];}(strm->raids[*]), strm->raids); //Sort by date, ignoring the </> direction marker
				strm->raids = Array.uniq2(strm->raids);
				//Stream recommendation level (which could then be sorted on)
				strm->recommend = recommend;
				//Factors that would recommend someone:
				//+10 for each incoming raid within the last month
				//+20 for each incoming raid between 1 and 12 months ago
				//-20 for each outgoing raid within the last month
				//-5 for each outgoing raid between 1 and 12 months ago
				//+1 to +2 for having 100% to 125% of your viewers, scaling
				//+1 to +8 for having 100% to 0% of your viewers
				//+10 to +1 for having been live for 0-4 hours (above four hours, might be ending soon)
				//+10 for being in the same category
				//+7 if both of you are in creative categories but different ones
			}
			//End stream tags work
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
			sort(-follows->recommend[*], follows); //Sort by magic initially
			return render_template("raidfinder.md", ([
				"follows": cached_follows = Standards.JSON.encode(follows, Standards.JSON.ASCII_ONLY),
				"your_stream": Standards.JSON.encode(your_stream, Standards.JSON.ASCII_ONLY),
				"highlights": Standards.JSON.encode(highlights, Standards.JSON.ASCII_ONLY),
				"sortorders": ({"Magic", "Viewers", "Category", "Uptime", "Raided"}) * "\n* ",
				"all_raids": Standards.JSON.encode(all_raids[<99..]),
			]));
		}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);}); //TODO: Return a nice message if for=junk given
}
