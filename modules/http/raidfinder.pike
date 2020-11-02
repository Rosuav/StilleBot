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
		if (newnotes == "") m_delete(notes, (string)body->id);
		else notes[(string)body->id] = newnotes;
		persist_status->save();
		return (["error": 204]);
	}
	if (req->variables->use_cache && cached_follows) return render_template("raidfinder.md", (["follows": cached_follows]));
	//Legacy data (currently all data): Parse the outgoing raid log
	//Note that this cannot handle renames, and will 'lose' them.
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
	return uid->then(lambda(int u) {
			userid = u;
			string login = req->misc->session->user->login, disp = req->misc->session->user->display_name;
			if (mapping user = u != (int)req->misc->session->user->id && G->G->user_info[u])
			{
				login = user->login || user->name; //helix || kraken
				disp = user->display_name;
			}
			//TODO: Show these in the logged-in user's specified timezone (if we have a
			//channel for that user), or UTC. Apologize on the page if no TZ available.
			//TODO: If working on behalf of someone else, which tz should we use?
			foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n", string raid)
			{
				sscanf(raid, "[%d-%d-%d %*d:%*d:%*d] %s => %s", int y, int m, int d, string from, string to);
				if (!to) continue;
				if (from == login) raids[lower_case(to)] += ({sprintf("%d-%02d-%02d You raided %s", y, m, d, to)});
				if (to == disp) raids[from] += ({sprintf("%d-%02d-%02d %s raided you", y, m, d, from)});
			}
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
				write("user_id: %O\n", strm->user_id);
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
			//NOTE: Notes come from your *login* userid, unaffected by any for= annotation.
			mapping notes = persist_status->path("raidnotes")[(string)req->misc->session->user->id];
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
				int swap = otheruid < userid;
				array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[swap ? userid : otheruid];
				foreach (raids || ({ }), mapping raid)
				{
					write("DEBUG RAID LOG: %O\n", raid);
					//TODO: Translate these by timezone (if available)
					object time = Calendar.ISO.Second("unix", raid->time);
					if (swap != raid->outgoing)
						strm->raids += ({sprintf("%s You raided %s", time->format_ymd(), raid->to)});
					else
						strm->raids += ({sprintf("%s %s raided you", time->format_ymd(), raid->to)});
				}
			}
			//End stream tags work
			return render_template("raidfinder.md", ([
				"follows": cached_follows = Standards.JSON.encode(follows, Standards.JSON.ASCII_ONLY),
				"your_stream": Standards.JSON.encode(your_stream, Standards.JSON.ASCII_ONLY),
			]));
		}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);}); //TODO: Return a nice message if for=junk given
}
