inherit http_endpoint;
/* Raid target finder
  - Show how many viewers *you* have, somewhere.
  - Raid tracking works only for channels that I track, but I don't have to bot for them.
  - Identify people by user ID if poss, not channel name
  - Also log incoming raids perhaps? Would be useful for other reasons too.
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
	if (req->variables->use_cache && cached_follows) return render_template("raidfinder.md", (["follows": cached_follows]));
	//Legacy data (currently all data): Parse the outgoing raid log
	//Note that this cannot handle renames, and will 'lose' them.
	string login = req->misc->session->user->login, disp = req->misc->session->user->display_name;
	int userid = (int)req->misc->session->user->id;
	write("%O %O %O\n", userid, login, disp);
	//TODO: Show these in the logged-in user's specified timezone (if we have a
	//channel for that user), or UTC. Apologize on the page if no TZ available.
	mapping raids = ([]);
	foreach ((Stdio.read_file("outgoing_raids.log") || "") / "\n", string raid)
	{
		sscanf(raid, "[%d-%d-%d %*d:%*d:%*d] %s => %s", int y, int m, int d, string from, string to);
		if (!to) continue;
		if (from == login) raids[lower_case(to)] += ({sprintf("%d-%02d-%02d You raided %s", y, m, d, to)});
		if (to == disp) raids[from] += ({sprintf("%d-%02d-%02d %s raided you", y, m, d, from)});
	}
	//Once raids get tracked by user IDs (and stored in persist_status),
	//they can be added to raids[] using numeric keys.
	array follows;
	mapping(int:array(string)) channel_tags = ([]);
	int your_viewers; string your_category;
	return twitch_api_request("https://api.twitch.tv/kraken/streams/followed?limit=100",
			(["Authorization": "OAuth " + req->misc->session->token]))
		->then(lambda(mapping info) {
			follows = info->streams;
			//All this work is just to get the stream tags (and some info about your own stream)
			array(int) channels = follows->channel->_id;
			channels += ({(int)req->misc->session->user->id});
			//TODO: Paginate if >100
			write("Fetching %d streams...\n", sizeof(channels));
			return twitch_api_request("https://api.twitch.tv/helix/streams?first=100" + sprintf("%{&user_id=%d%}", channels));
		})->then(lambda(mapping info) {
			if (!G->G->tagnames) G->G->tagnames = ([]);
			multiset all_tags = (<>);
			foreach (info->data, mapping strm)
			{
				channel_tags[(int)strm->user_id] = strm->tag_ids;
				if (strm->user_id == req->misc->session->user->id)
				{
					//Info about your own stream. Handy but doesn't go in the main display.
					//write("Your tags: %O\n", strm->tag_ids); //Is it worth trying to find people with similar tags?
					your_viewers = strm->viewer_count;
					your_category = strm->game_id;
					continue;
				}
				//all_tags |= (tag_ids &~ G->G->tagnames); //sorta kinda
				foreach (strm->tag_ids || ({ }), string tag)
					if (!G->G->tagnames[tag]) all_tags[tag] = 1;
			}
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
				int otheruid = (int)strm->user_id;
				int swap = otheruid < userid;
				array raids = persist_status->path("raids", (string)(swap ? otheruid : userid))[swap ? userid : otheruid];
				foreach (raids, mapping raid)
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
				"your_viewers": (string)your_viewers,
				"your_category": Standards.JSON.encode(G->G->category_names[your_category], Standards.JSON.ASCII_ONLY),
			]));
		}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);});
}
