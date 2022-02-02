//Can be invoked from the command line for tools or interactive API inspection.
#if !constant(G)
mapping G = (["G":([])]);
mapping persist_config = (["channels": ({ }), "ircsettings": Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([])]);
mapping persist_status = ([]);
#endif

//Place a request to the API. Returns a Future that will be resolved with a fully
//decoded result (a mapping of Unicode text, generally), or rejects if Twitch or
//the network failed the request.
Concurrent.Future request(Protocols.HTTP.Session.URL url, mapping|void headers, mapping|void options)
{
	headers = (headers || ([])) + ([]);
	options = options || ([]);
	if (options->username)
	{
		//Convert a user name into a user ID. Assumes the URL is a string with {{USER}} where the ID belongs.
		mapping usernames;
		if (stringp(options->username)) usernames = (["{{USER}}": options->username]);
		else usernames = options->username + ([]);
		array reqs = ({ });
		foreach (usernames; string tag; string user)
		{
			usernames[tag] = user = lower_case(user);
			if (mapping info = G->G->user_info[user]) usernames[tag] = (string)info->id; //Local cache lookup where possible
			else reqs += ({get_user_info(user, "login")
				->then(lambda(mapping info) {replace(usernames, info->login, info->id);})
			});
		}
		if (sizeof(reqs) > 1) reqs = ({Concurrent.all(@reqs)});
		if (sizeof(reqs)) return reqs[0]->then(lambda() {
			return request(replace(url, usernames), headers, options - (<"username">));
		});
		url = replace(url, usernames);
		//If we found everything in cache, carry on with a modified URL.
	}
	string body = options->data;
	if (options->json) {
		headers["Content-Type"] = "application/json";
		body = Standards.JSON.encode(options->json);
	}
	string method = options->method || (body ? "POST" : "GET");
	headers["Accept"] = "application/vnd.twitchtv.v5+json"; //Only needed for Kraken but doesn't seem to hurt
	if (!headers["Authorization"])
	{
		if (options->authtype == "app") {
			//App authorization token. If we don't have one, get one.
			if (!G->G->app_access_token || G->G->app_access_token_expiry < time()) {
				if (!persist_config["ircsettings"]["clientsecret"]) return Concurrent.reject(({sprintf("%s\nUnable to use app auth without a client secret\n", url), backtrace()}));
				if (G->G->app_access_token_expiry == -1) {
					//TODO: Wait until the other request returns.
					//For now we just sleep and try again.
					return Concurrent.resolve(0)->delay(2)->then(lambda() {return request(url, headers, options);});
				}
				G->G->app_access_token_expiry = -1; //Prevent spinning
				Standards.URI uri = Standards.URI("https://id.twitch.tv/oauth2/token");
				//As below, uri->set_query_variables() doesn't correctly encode query data.
				uri->query = Protocols.HTTP.http_encode_query(([
					"client_id": persist_config["ircsettings"]["clientid"],
					"client_secret": persist_config["ircsettings"]["clientsecret"],
					"grant_type": "client_credentials",
				]));
				return request(uri, ([]), (["method": "POST"]))
					->then(lambda (mapping data) {
						G->G->app_access_token = data->access_token;
						G->G->app_access_token_expiry = time() + data->expires_in - 120;
						//If this becomes a continue function, we could just fall through
						//instead of calling ourselves recursively.
						return request(url, headers, options);
					});
			}
			headers->Authorization = "Bearer " + G->G->app_access_token;
		}
		else {
			//Under what circumstances do we need to use "OAuth <token>" instead?
			//In Mustard Mine, the only remaining place is PUT /kraken/channels which we
			//don't use here, but are there any others?
			//20200511: It seems emote lookups require "OAuth" instead of "Bearer". Sheesh.
			sscanf(persist_config["ircsettings"]["pass"] || "", "oauth:%s", string pass);
			if (pass) headers["Authorization"] = (options->authtype || "Bearer") + " " + pass;
		}
	}
	if (string c = !headers["Client-ID"] && persist_config["ircsettings"]["clientid"])
		//Most requests require a Client ID. Not sure which don't, so just provide it (if not already set).
		headers["Client-ID"] = c;
	return Protocols.HTTP.Promise.do_method(method, url,
			Protocols.HTTP.Promise.Arguments((["headers": headers, "data": body])))
		->then(lambda(Protocols.HTTP.Promise.Result res) {
			int limit = (int)res->headers["ratelimit-limit"],
				left = (int)res->headers["ratelimit-remaining"];
			if (limit) write("Rate limit: %d/%d   \r", limit - left, limit); //Will usually get overwritten
			if (options->return_status) return res->status; //For requests not expected to have a body, but might have multiple success returns
			mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
			if (!mappingp(data)) return Concurrent.reject(({sprintf("%s\nUnparseable response\n%O\n", url, res->get()[..64]), backtrace()}));
			if (data->error && !options->return_errors) return Concurrent.reject(({sprintf("%s\nError from Twitch: %O (%O)\n%O\n", url, data->error, data->status, data), backtrace()}));
			return data;
		});
}

void notice_user_name(string login, string id) {
	//uid_to_name[(string)userid] maps the user names seen to the timestamps.
	//To detect renames, sort the keys and values in parallel; the most recent
	//change is represented by the last two keys.
	if (!login || !persist_status->path) return; //The latter check stops us from bombing in CLI usage
	id = (string)id; login = lower_case((string)login);
	mapping u2n = persist_status->path("uid_to_name", id);
	if (!u2n[login]) {u2n[login] = time(); persist_status->save();}
	//The name-to-UID mapping should be considered advisory, and useful mainly for recent ones.
	mapping n2u = persist_status->path("name_to_uid");
	if (n2u[login] != id) {n2u[login] = id; persist_status->save();}
}

//Will return from cache if available. Set type to "login" to look up by name, else uses ID.
Concurrent.Future get_users_info(array(int|string) users, string|void type)
{
	//Simplify things elsewhere: 0 yields 0 with no error. (Otherwise you'll
	//always get an array of mappings, or a rejection.)
	if (!users) return Concurrent.resolve(0);
	users -= ({0});

	if (type != "login") {type = "id"; users = (array(int))users;}
	else users = lower_case(((array(string))users)[*]);
	array results = allocate(sizeof(users));
	array lookups = ({ });
	foreach (users; int i; int|string u)
	{
		if (mapping info = G->G->user_info[u]) results[i] = info;
		else lookups += ({(string)u});
	}
	if (!sizeof(lookups)) return Concurrent.resolve(results); //Got 'em all from cache.
	return request(sprintf("https://api.twitch.tv/helix/users?%{" + type + "=%s&%}", Protocols.HTTP.uri_encode(lookups[*])))
		->then(lambda(mapping data) {
			foreach (data->data, mapping info) {
				G->G->user_info[info->login] = G->G->user_info[(int)info->id] = info;
				notice_user_name(info->login, info->id);
			}
			foreach (users; int i; int|string u)
			{
				if (mapping info = G->G->user_info[u]) results[i] = info;
				//Note that the returned error will only ever name a single failed lookup.
				//It's entirely possible that others failed too, but it probably won't matter.
				else return Concurrent.reject(({"User not found: " + u + "\n", backtrace()}));
			}
			return results;
		});
}

//As above but only a single user's info. For convenience, 0 will yield 0 without an error.
Concurrent.Future get_user_info(int|string user, string|void type)
{
	return get_users_info(({user}), type)->then(lambda(array(mapping) info) {return sizeof(info) && info[0];});
}

//Convenience shorthand when all you need is the ID
Concurrent.Future get_user_id(string user)
{
	return get_users_info(({user}), "login")->then(lambda(array(mapping) info) {return sizeof(info) && (int)info[0]->id;});
}

Concurrent.Future get_helix_paginated(string url, mapping|void query, mapping|void headers, mapping|void options, int|void debug)
{
	array data = ({ });
	Standards.URI uri = Standards.URI(url);
	query = (query || ([])) + ([]);
	if (!query->first) query->first = "100"; //Default to the largest page permitted.
	//NOTE: uri->set_query_variables() doesn't correctly encode query data.
	uri->query = Protocols.HTTP.http_encode_query(query);
	int empty = 0;
	if (debug) werror("get_helix_paginated %O %O\n", url, uri->query);
	mixed nextpage(mapping raw)
	{
		if (!raw->data) return Concurrent.reject(({"Unparseable response\n", backtrace()}));
		if (debug)
		{
			string pg = (raw->pagination && raw->pagination->cursor) || "";
			catch {pg = MIME.decode_base64(pg);};
			if (sscanf(pg, "{\"b\":{\"Cursor\":\"%[-0-9.T:Z]\"},\"a\":{\"Cursor\":\"%[-0-9.T:Z]\"}}",
				string b, string a) && a)
			{
				pg = sprintf("FROM %s TO %s", b, a);
				/*
				object t = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", a)->add(-10);
				a = sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
					t->year_no(), t->month_no(), t->month_day(),
					t->hour_no(), t->minute_no(), t->second_no(),
				);
				raw->pagination->cursor = sprintf("{\"b\":{\"Cursor\":\"%s\"},\"a\":{\"Cursor\":\"%s\"}}", b, a);
				*/
			}
			werror("Next page: %d data, pg %s\n", sizeof(raw->data), pg);
		}
		data += raw->data;
		if (!raw->pagination || !raw->pagination->cursor) return data;
		//Possible Twitch API bug: If the returned cursor is precisely "IA",
		//it's probably the end of the results. It's come up more than once
		//in the past, and might well happen again.
		if (raw->pagination->cursor == "IA") return data;
		//Another possible Twitch bug: Sometimes the cursor is constantly
		//changing, but we get no data each time. In case this happens
		//once by chance, we have a "three strikes and WE'RE out" policy.
		if (!sizeof(raw->data) && ++empty >= 3) return data;
		//uri->add_query_variable("after", raw->pagination->cursor);
		query["after"] = raw->pagination->cursor; uri->query = Protocols.HTTP.http_encode_query(query);
		return request(uri, headers, options)->then(nextpage);
	}
	return request(uri, headers, options)->then(nextpage);
}

//Doesn't help, but it's certainly very interesting.
//Attempt to probe the Helix pagination issues I've been seeing by paginating on two different
//numbers and then combining the results. It's possible that there are two page sizes that would
//catch everything, but at the moment, I haven't managed to find the magic pair. Still, it's been
//interesting (in the Wash sense) delving into this. Using 100 and 99 is 
Concurrent.Future get_helix_bifurcated(string url, mapping|void query, mapping|void headers, int|void debug)
{
	query = query || ([]);
	return get_helix_paginated(url, query | (["first": "100"]), headers, debug)->then(lambda(array data1) {
		return get_helix_paginated(url, query | (["first": "97"]), headers, debug)->then(lambda(array data2) {
			multiset seen = (<>);
			foreach (data1, mixed x) seen[sprintf("%O", x)] = 1;
			array ret = data1;
			foreach (data2, mixed x) if (!seen[sprintf("%O", x)]) ret += ({x});
			if (debug) werror("Got %d + %d = %d results\n", sizeof(data1), sizeof(data2), sizeof(ret));
			return ret;
		});
	});
}

//Returns "offline" if not broadcasting, or a channel uptime.
continue Concurrent.Future|string channel_still_broadcasting(string|int chan) {
	if (stringp(chan)) chan = yield(get_user_id(chan));
	array initial = request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1")->data;
	//If there are no videos found, then presumably the person isn't live, since
	//(even if VODs are disabled) the current livestream always shows up.
	if (!sizeof(initial)) return "offline";
	mixed _ = yield(task_sleep(1.5));
	array second = request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1")->data;
	//When a channel is offline, the VOD doesn't grow in length.
	if (!sizeof(second) || second[0]->duration == initial[0]->duration) return "offline";
	return second[0]->duration;
}

Concurrent.Future get_channel_info(string name)
{
	return request("https://api.twitch.tv/helix/channels?broadcaster_id={{USER}}", ([]), (["username": name]))
	->then(lambda(mapping info) {
		info = info->data[0];
		//Provide Kraken-like attribute names for convenience
		//TODO: Find everything that uses the Kraken names and correct them
		info->game = info->game_name;
		info->display_name = info->broadcaster_name;
		info->url = "https://twitch.tv/" + info->broadcaster_name; //Is this reliable??
		info->_id = info->broadcaster_id;
		info->status = info->title;
		if (!G->G->channel_info[name]) G->G->channel_info[name] = info; //Autocache
		return info;
		/* Things we make use of:
		 * game => category
		 * mature => boolean, true if has click-through warning
		 * display_name => preferred way to show the channel name
		 * url => just "https://www.twitch.tv/"+name if we want to hack it
		 * status => stream title
		 * _id => numeric user ID
		 */
	}, lambda(mixed err) {
		if (has_prefix(err[0], "User not found: ")) {
			werror(err[0]);
			if (!G->G->channel_info[name]) G->G->channel_info[name] = ([ ]);
		}
		else return Concurrent.reject(err);
	});
}

Concurrent.Future get_video_info(string name)
{
	//20210716: Requires Kraken functionality not available in Helix, incl list of resolutions.
	return request("https://api.twitch.tv/kraken/channels/{{USER}}/videos?broadcast_type=archive&limit=1", ([]), (["username": name]))
		->then(lambda(mapping info) {return info->videos[0];});
}

void streaminfo(array data)
{
	//First, quickly remap the array into a lookup mapping
	//This helps us ensure that we look up those we care about, and no others.
	mapping channels = ([]);
	foreach (data, mapping chan) channels[lower_case(chan->user_login)] = chan;
	//Now we check over our own list of channels. Anything absent is assumed offline.
	foreach (indices(persist_config["channels"]), string chan) if (chan[0] != '!')
		stream_status(chan, channels[chan]);
}

continue Concurrent.Future cache_game_names(string game_id)
{
	if (mixed ex = catch {
		array games = yield(get_helix_paginated("https://api.twitch.tv/helix/games/top", (["first":"100"])));
		foreach (games, mapping game) G->G->category_names[game->id] = game->name;
		write("Fetched %d games, total %d\n", sizeof(games), sizeof(G->G->category_names));
		if (!G->G->category_names[game_id]) {
			//We were specifically asked for this game ID. Explicitly ask Twitch for it.
			mapping info = yield(request("https://api.twitch.tv/helix/games?id=" + game_id));
			if (!sizeof(info->data)) werror("Unable to fetch game info for ID %O\n", game_id);
			else if (info->data[0]->id != game_id) werror("???? Asked for game %O but got %O ????\n", game_id, info->data[0]->id);
			else G->G->category_names[game_id] = info->data[0]->name;
		}
	}) {
		werror("Error fetching games:\n%s\n", describe_backtrace(ex));
	}
}

continue Concurrent.Future|array translate_tag_ids(array tag_ids) {
	array got_tags = ({ });
	if (!G->G->all_stream_tags) {
		G->G->all_stream_tags = ([]);
		got_tags = yield(get_helix_paginated("https://api.twitch.tv/helix/tags/streams"));
	}
	else {
		multiset need_tags = (<>);
		foreach (tag_ids || ({ }), string tag)
			if (!G->G->all_stream_tags[tag]) need_tags[tag] = 1;
		if (sizeof(need_tags)) {
			//Normally we'll have all the tags from the check up above, but in case, we catch more here.
			write("Fetching %d tags...\n", sizeof(need_tags));
			got_tags = yield(get_helix_paginated("https://api.twitch.tv/helix/tags/streams", (["tag_id": (array)need_tags])));
		}
	}
	foreach (got_tags, mapping tag) G->G->all_stream_tags[tag->tag_id] = ([
		"id": tag->tag_id,
		"name": tag->localization_names["en-us"],
		"desc": tag->localization_descriptions["en-us"],
		"auto": tag->is_auto,
	]);
	//Every tag ID should now be in the cache, unless there's a bad ID or something.
	return G->G->all_stream_tags[tag_ids[*]];
}

int fetching_game_names = 0;
//Attempt to construct a channel info mapping from the stream info
//May use other caches of information. If unable to build the full
//channel info, returns 0 (recommendation: fetch info via Kraken).
mapping build_channel_info(mapping stream)
{
	mapping ret = ([]);
	ret->game_id = stream->game_id;
	if (!(ret->game = G->G->category_names[stream->game_id]))
	{
		if (stream->game_id != "0" && stream->game_id != "" && !fetching_game_names)
		{
			write("Fetching games because we know %d games but not %O\n",
				sizeof(G->G->category_names), stream->game_id);
			//Note that category_names is NOT cleared before we start. There
			//have been many instances where games aren't being detected, and I
			//suspect that either some games are being omitted from the return
			//value, or they're slipping in the gap between pages due to changes
			//in the ordering of the "top 100" and "next 100". It should be safe
			//to retain any previous ones seen this run.
			fetching_game_names = 1;
			spawn_task(cache_game_names(stream->game_id)) {fetching_game_names = 0;};
		}
		return 0;
	}
	//TODO: ret->mature, if possible
	ret->display_name = stream->user_name;
	ret->url = "https://www.twitch.tv/" + lower_case(stream->user_name); //TODO: Get the actual login, which may be different
	ret->status = stream->title;
	ret->online_type = stream->type; //Really, THIS should be called "status" (eg "live"), and "status" should be called Title. But whatevs.
	ret->_id = ret->user_id = stream->user_id;
	ret->_raw = stream; //Avoid using this except for testing
	//Add anything else here that might be of interest
	return ret;
}

continue Concurrent.Future|mapping save_channel_info(string name, mapping info) {
	//Attempt to gather channel info from the stream info. If we
	//can't, we'll get that info via Kraken.
	mapping synthesized = build_channel_info(info);
	if (!synthesized) {
		if (info->game_id != "") write("SYNTHESIS FAILED - maybe bad game? %O\n", info->game_id);
		synthesized = yield(get_channel_info(name));
	}
	synthesized->viewer_count = info->viewer_count;
	synthesized->tags = yield(translate_tag_ids(info->tag_ids || ({ })));
	synthesized->tag_names = sprintf("[%s]", synthesized->tags->name[*]) * ", ";
	int changed = 0;
	foreach ("game status tag_names" / " ", string attr)
		changed += synthesized[attr] != G->G->channel_info[name][?attr];
	G->G->channel_info[name] = synthesized;
	if (changed) {
		object chan = G->G->irc->channels["#"+name];
		if (chan) chan->trigger_special("!channelsetup", ([
			//Synthesize a basic person mapping
			"user": name,
			"displayname": info->user_name,
			"uid": (string)info->user_id,
		]), ([
			"{category}": synthesized->game,
			"{title}": synthesized->status,
			"{tag_names}": synthesized->tag_names,
			"{tag_ids}": synthesized->tags->id * ", ",
		]));
	}
}

//Receive stream status, either polled or by notification
void stream_status(string name, mapping info)
{
	if (!info)
	{
		if (!G->G->channel_info[name])
		{
			//Make sure we know about all channels
			write("** Channel %s isn't online - fetching last-known state **\n", name);
			get_channel_info(name);
		}
		else m_delete(G->G->channel_info[name], "online_type");
		if (object started = m_delete(G->G->stream_online_since, name))
		{
			write("** Channel %s noticed offline at %s **\n", name, Calendar.now()->format_nice());
			object chan = G->G->irc->channels["#"+name];
			runhooks("channel-offline", 0, name);
			int uptime = time() - started->unix_time();
			if (chan) chan->trigger_special("!channeloffline", ([
				//Synthesize a basic person mapping
				"user": name,
				"displayname": name, //Might not have the actual display name handy (get_channel_info is async)
				"uid": persist_status->path("name_to_uid")[name] || "0", //It should always be there, but if someone renames while live, who knows.
			]), ([
				"{uptime}": (string)uptime,
				"{uptime_hms}": describe_time_short(uptime),
				"{uptime_english}": describe_time(uptime),
			]));
			mapping vstat = m_delete(G->G->viewer_stats, name);
			if (sizeof(vstat->half_hour) == 30)
			{
				mapping status = persist_status["stream_stats"];
				if (!status)
				{
					//Migrate from old persist
					status = ([]);
					foreach (persist_config["channels"]; string name; mapping chan)
					{
						array stats = m_delete(chan, "stream_stats");
						if (stats) status[name] = stats;
					}
					persist_status["stream_stats"] = status;
					persist_config->save();
				}
				status[name] += ({([
					"start": vstat->start, "end": time(),
					"viewers_high": vstat->high_half_hour,
					"viewers_low": vstat->low_half_hour,
				])});
				persist_status->save();
			}
		}
	}
	else
	{
		object started = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->started_at);
		if (!G->G->stream_online_since[name])
		{
			//Is there a cleaner way to say "convert to local time"?
			object started_here = started->set_timezone(Calendar.now()->timezone());
			write("** Channel %s went online at %s **\n", name, started_here->format_nice());
			object chan = G->G->irc->channels["#"+name];
			runhooks("channel-online", 0, name);
			int uptime = time() - started->unix_time();
			if (chan) chan->trigger_special("!channelonline", ([
				//Synthesize a basic person mapping
				"user": name,
				"displayname": info->user_name,
				"uid": (string)info->user_id,
			]), ([
				"{uptime}": (string)uptime,
				"{uptime_hms}": describe_time_short(uptime),
				"{uptime_english}": describe_time(uptime),
			]));
		}
		spawn_task(save_channel_info(name, info));
		notice_user_name(name, info->user_id);
		G->G->stream_online_since[name] = started;
		int viewers = info->viewer_count;
		//Calculate half-hour rolling average, and then do stats on that
		//Record each stream's highest and lowest half-hour average, and maybe the overall average (not the average of the averages)
		//To maybe do: Offer a graph showing the channel's progress. Probably now done better by
		//StreamLabs, but we could have our own graph to double-check and maybe learn about
		//different measuring/reporting techniques.
		mapping vstat = G->G->viewer_stats; if (!vstat) vstat = G->G->viewer_stats = ([]);
		if (!vstat[name]) vstat[name] = (["start": time()]); //The stats might not have started at stream start, eg if bot wasn't running
		vstat = vstat[name]; //Focus on this channel.
		vstat->half_hour += ({viewers});
		if (sizeof(vstat->half_hour) >= 30)
		{
			vstat->half_hour = vstat->half_hour[<29..]; //Keep just the last half hour of stats
			int avg = `+(@vstat->half_hour) / 30;
			vstat->high_half_hour = max(vstat->high_half_hour, avg);
			if (!has_index(vstat, "low_half_hour")) vstat->low_half_hour = avg;
			else vstat->low_half_hour = min(vstat->low_half_hour, avg);
		}
	}
}

Concurrent.Future check_following(string user, string chan)
{
	return request("https://api.twitch.tv/helix/users/follows?from_id={{USER}}&to_id={{CHAN}}", ([]),
		(["username": (["{{USER}}": user, "{{CHAN}}": chan])]))
	->then(lambda(mapping info) {
		if (!sizeof(info->data)) {
			//Not following. Explicitly store that info.
			mapping foll = G_G_("participants", chan, user);
			foll->following = 0;
			return ({user, chan, foll});
		}
		mapping foll = G_G_("participants", chan, user);
		foll->following = "since " + info->data[0]->followed_at;
		return ({user, chan, foll});
	}, lambda(mixed err) {
		return ({user, chan, ([])}); //Unknown error. Ignore it (most likely the user will be assumed not to be a follower).
	});
}

//Fetch a stream's schedule, up to N events within the next M seconds.
continue Concurrent.Future|array get_stream_schedule(int|string channel, int rewind, int maxevents, int maxtime) {
	int id = (int)channel || yield(get_user_id(channel));
	if (!id) return ({ });
	//NOTE: Do not use get_helix_paginated here as the events probably go on forever.
	array events = ({ });
	string cursor = "";
	object begin = Calendar.ISO.Second()->set_timezone("UTC")->add(-rewind);
	string starttime = begin->format_ymd() + "T" + begin->format_tod() + "Z";
	object limit = Calendar.ISO.Second()->set_timezone("UTC")->add(maxtime);
	string cutoff = limit->format_ymd() + "T" + limit->format_tod() + "Z";
	while (1) {
		mapping info = yield(request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id
			+ "&start_time=" + starttime + "&after=" + cursor + "&first=25",
			([]), (["return_errors": 1])));
		if (info->error) break; //Probably 404, schedule not found.
		cursor = info->pagination->?cursor;
		foreach (info->data->segments, mapping ev) {
			if (ev->start_time > cutoff) return events;
			events += ({ev});
			if (sizeof(events) >= maxevents) return events;
		}
		if (!cursor) break;
	}
	return events;
}

class EventSub(string hookname, string type, string version, function callback) {
	Crypto.SHA256.HMAC signer;
	multiset(string) have_subs = (<>);
	protected void create() {
		if (!persist_status->path) return;
		mapping secrets = persist_status->path("eventhook_secret");
		if (!secrets[hookname]) {
			secrets[hookname] = MIME.encode_base64(random_string(15));
			//Save the secret. This is unencrypted and potentially could be leaked.
			//The attack surface is fairly small, though - at worst, an attacker
			//could forge a notification from Twitch, causing us to... whatever the
			//event hook triggers, probably some sort of API call. I guess you could
			//disrupt the hype train tracker's display or something. Congrats.
			persist_status->save();
		}
		signer = Crypto.SHA256.HMAC(secrets[hookname]);
		if (!G->G->eventhook_types) G->G->eventhook_types = ([]);
		if (object other = G->G->eventhook_types[hookname]) have_subs = other->have_subs;
		G->G->eventhook_types[hookname] = this;
	}
	protected void `()(string|mixed arg, mapping condition) {
		if (!stringp(arg)) arg = (string)arg; //It really should be a string
		if (have_subs[arg]) return;
		request("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([
			"authtype": "app",
			"json": ([
				"type": type, "version": version,
				"condition": condition,
				"transport": ([
					"method": "webhook",
					"callback": sprintf("%s/junket?%s=%s",
						persist_config["ircsettings"]["http_address"],
						hookname, arg,
					),
					"secret": persist_status->path("eventhook_secret")[hookname],
				]),
			]),
		]))
		->then(lambda(mixed ret) {
			//werror("EventSub response: %O\n", ret);
		}, lambda(mixed ret) {
			//Could be 409 Conflict if we already have one. What should we do if
			//we want to change the signer???
			werror("EventSub error response - %s=%s\n%s\n", hookname, arg, describe_error(ret));
		});
	}
}

EventSub new_follower = EventSub("follower", "channel.follow", "1") { [string chan, mapping follower] = __ARGS__;
	notice_user_name(follower->user_login, follower->user_id);
	if (object channel = G->G->irc->channels["#" + chan])
		check_following(follower->user_login, chan)->then() {
			//Sometimes bots will follow-unfollow. Avoid spamming chat with meaningless follow messages.
			if (__ARGS__[0][2]->following) channel->trigger_special("!follower", ([
				"user": follower->user_login,
				"displayname": follower->user_name,
			]), ([]));
		};
};
EventSub raidin = EventSub("raidin", "channel.raid", "1") {Stdio.append_file("evthook.log", sprintf("EVENT: Raid incoming [%d, %O]: %O\n", time(), @__ARGS__));};
EventSub raidout = EventSub("raidout", "channel.raid", "1") {Stdio.append_file("evthook.log", sprintf("EVENT: Raid outgoing [%d, %O]: %O\n", time(), @__ARGS__));};

void check_hooks(array eventhooks)
{
	foreach (G->G->eventhook_types;; object handler) handler->have_subs = (<>);
	foreach (eventhooks, mapping hook) {
		sscanf(hook->transport->callback || "", "http%*[s]://%*s/junket?%s=%s", string type, string arg);
		object handler = G->G->eventhook_types[type];
		if (!handler) {
			write("Deleting eventhook: %O\n", hook);
			request("https://api.twitch.tv/helix/eventsub/subscriptions?id=" + hook->id,
				([]), (["method": "DELETE", "authtype": "app", "return_status": 1]));
		}
		else handler->have_subs[arg] = 1;
	}

	mapping secrets = persist_status->path("eventhook_secret");
	if (sizeof(secrets - G->G->eventhook_types)) {
		//This could be done unconditionally, but there's no point doing an unnecessary save
		secrets = G->G->eventhook_types & secrets;
		persist_status->save();
	}

	foreach (persist_config["channels"] || ([]); string chan; mapping cfg)
	{
		if (!cfg->active) continue;
		mapping c = G->G->channel_info[chan];
		int userid = c->?_id;
		if (!userid) continue; //We need the user ID for this. If we don't have it, the hook can be retried later. (This also suppresses pseudo-channels.)
		new_follower(chan, (["broadcaster_user_id": (string)userid]));
		raidin(chan, (["to_broadcaster_user_id": (string)userid]));
		raidout(chan, (["from_broadcaster_user_id": (string)userid]));
	}
}

void poll()
{
	G->G->poll_call_out = call_out(poll, 60); //Maybe make the poll interval customizable?
	array chan = indices(persist_config["channels"] || ({ }));
	chan = filter(chan) {return __ARGS__[0][0] != '!';};
	if (!sizeof(chan)) return; //Nothing to check.
	G->G->stream_online_since &= (multiset)chan; //Prune any "channel online" statuses for channels we don't track any more
	//Note: There's a slight TOCTOU here - the list of channel names will be
	//re-checked from persist_config when the response comes in. If there are
	//channels that we get info for and don't need, ignore them; if there are
	//some that we wanted but didn't get, we'll just think they're offline
	//until the next poll.
	get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_login": chan, "first": "100"]))
		->on_success(streaminfo);
	//There has been an issue with failures and a rate limiting from Twitch.
	//I suspect that something is automatically retrying AND the sixty-sec
	//poll is triggering again, causing stacking requests. Look into it if
	//possible. Otherwise, there'll be a bit of outage (cooldown) any time
	//I hit this sort of problem.
	string addr = persist_config["ircsettings"]["http_address"];
	if (addr && addr != "")
		get_helix_paginated("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([]), (["authtype": "app"]))
			->on_success(check_hooks);
}

int req(string url, string|void username) //Returns 0 to suppress Hilfe warning.
{
	//NOTE: You need the helix/ or kraken/ prefix to indicate which API to use.
	if (!has_prefix(url, "http")) url = "https://api.twitch.tv/" + url[url[0]=='/'..];
	request(url, 0, (["username": username]))->then() {[mixed info] = __ARGS__;
		write("%O\n", info);
		//TODO: Surely there's a better way to access the history object for the running Hilfe...
		object history = function_object(all_constants()["backend_thread"]->backtrace()[0]->args[0])->history;
		history->push(info);
	};
}

protected void create()
{
	if (!G->G->stream_online_since) G->G->stream_online_since = ([]);
	if (!G->G->channel_info) G->G->channel_info = ([]);
	if (!G->G->category_names) G->G->category_names = ([]);
	if (!G->G->user_info) G->G->user_info = ([]);

	if (!persist_config["allcmds_migrated"]) {
		//CJA 20210726: Formerly, "allcmds" meant active and allcmds, and "httponly"
		//meant active and (presumably) not allcmds. Now, active is independent of
		//allcmds, so it needs to be migrated (but only once - don't have allcmds
		//permanently imply active, as that would be v confusing).
		foreach (persist_config["channels"] || ([]); string chan; mapping cfg) {
			if (m_delete(cfg, "httponly") || cfg->allcmds) cfg->active = 1;
		}
		persist_config["allcmds_migrated"] = 1;
	}

	remove_call_out(G->G->poll_call_out);
	#if !constant(INTERACTIVE)
	poll();
	#endif
	add_constant("get_channel_info", get_channel_info);
	add_constant("check_following", check_following);
	add_constant("get_video_info", get_video_info);
	add_constant("twitch_api_request", request);
	add_constant("get_helix_paginated", get_helix_paginated);
	add_constant("get_user_id", get_user_id);
	add_constant("get_user_info", get_user_info);
	add_constant("get_users_info", get_users_info);
	add_constant("notice_user_name", notice_user_name);
	add_constant("translate_tag_ids", translate_tag_ids);
	add_constant("EventSub", EventSub);
	add_constant("get_stream_schedule", get_stream_schedule);
}

#if !constant(G)
void runhooks(mixed ... args) { }
mapping G_G_(mixed ... args) {return ([]);}
mixed task_sleep(mixed ... args) {error("task_sleep is not currently supported in CLI mode\n");}
mixed spawn_task(mixed ... args) {error("spawn_task is not currently supported in CLI mode\n");}

int requests;

mapping decode(string data)
{
	mapping info = Standards.JSON.decode(data);
	if (info && !info->error) return info;
	if (!info) write("Request failed - server down?\n");
	else write("%d %s: %s\n", info->status, info->error, info->message||"(unknown)");
	if (!--requests) exit(0);
}

//Lifted from globals because I can't be bothered refactoring
string describe_time_short(int tm)
{
	string msg = "";
	int secs = tm;
	if (int t = secs/86400) {msg += sprintf("%d, ", t); secs %= 86400;}
	if (tm >= 3600) msg += sprintf("%02d:%02d:%02d", secs/3600, (secs%3600)/60, secs%60);
	else if (tm >= 60) msg += sprintf("%02d:%02d", secs/60, secs%60);
	else msg += sprintf("%02d", tm);
	return msg;
}
string describe_time(int tm)
{
	string msg = "";
	if (int t = tm/86400) {msg += sprintf(", %d day%s", t, t>1?"s":""); tm %= 86400;}
	if (int t = tm/3600) {msg += sprintf(", %d hour%s", t, t>1?"s":""); tm %= 3600;}
	if (int t = tm/60) {msg += sprintf(", %d minute%s", t, t>1?"s":""); tm %= 60;}
	if (tm) msg += sprintf(", %d second%s", tm, tm>1?"s":"");
	return msg[2..];
}

void streaminfo_display(mapping info)
{
	if (sizeof(info->data))
	{
		object started = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->data[0]->started_at);
		write("Channel went online at %s\n", started->format_nice());
		write("Uptime: %s\n", describe_time_short(started->distance(Calendar.now())->how_many(Calendar.Second())));
	}
	else write("Channel is offline.\n");
	if (!--requests) exit(0);
}
Concurrent.Future chaninfo_display(mapping info)
{
	if (info->mature) write("[MATURE] ");
	write("%s was last seen playing %s, at %s - %s\n",
		info->display_name, string_to_utf8(info->game || "(null)"), info->url, string_to_utf8(info->status || "(null)"));
	return request("https://api.twitch.tv/helix/streams?user_id=" + info->_id)->then(streaminfo_display);
}
void followinfo_display(array args)
{
	[string user, string chan, mapping info] = args;
	if (!info->following) write("%s is not following %s.\n", user, chan);
	else write("%s has been following %s %s.\n", user, chan, (info->following/"T")[0]);
	if (!--requests) exit(0);
}

void transcoding_display(mapping info)
{
	if (info->status == 404 || !sizeof(info->videos))
	{
		write("Error fetching transcoding info: %O\n", info);
		if (!--requests) exit(0);
		return;
	}
	int total = 0, tc = 0;
	foreach (info->videos, mapping videoinfo)
	{
		mapping res = videoinfo->resolutions;
		if (!res || !sizeof(res)) return; //Shouldn't happen
		string dflt = m_delete(res, "chunked") || "?? unknown res ??"; //Not sure if "chunked" can ever be missing
		write("[%s] %-9s %s - %s\n", videoinfo->created_at, dflt, sizeof(res) ? "TC" : "  ", videoinfo->game);
		++total; if (sizeof(res)) ++tc;
	}
	write("Had transcoding for %d/%d streams (%d%%)\n", tc, total, tc * 100 / total);
	if (!--requests) exit(0);
}

void clips_display(string channel)
{
	string dir = "../clips/" + channel;
	array files = get_dir(dir);
	multiset unseen;
	if (files) unseen = (multiset)glob("*.json", files);
	//get_helix_paginated(string url, mapping|void query, mapping|void headers)
	get_user_id(channel)->then(lambda (int userid) {
		return get_helix_paginated("https://api.twitch.tv/helix/clips",
			(["broadcaster_id": (string)userid, "first": "100"]));
	})->then(lambda (array clips) {
		foreach (clips, mapping clip)
		{
			if (unseen)
			{
				unseen[clip->id + ".json"] = 0;
				Stdio.write_file(dir + "/" + clip->id + ".json", Standards.JSON.encode(clip, 7));
			}
			write(string_to_utf8(sprintf("[%s] %s %s - %s\n", clip->created_at, clip->id, clip->creator_name, clip->title)));
		}
		if (unseen && sizeof(unseen))
			write("%d deleted clips:\n%{\t%s\n%}", sizeof(unseen), sort((array)unseen));
		if (!--requests) exit(0);
	}, lambda (mapping err) {
		write("Error fetching clips: %O\n", err);
		if (!--requests) exit(0);
	});
}

void raids_display(string ch)
{
	get_user_id(ch)->then(lambda (int id) {
		array raiddescs = ({ }), times = ({ });
		foreach (persist_status->raids[(string)id] || ([]); int otherid; array raids) {
			foreach (raids, mapping raid)
			{
				if (raid->outgoing)
					raiddescs += ({sprintf("RAID>> %s raided %s on %s", raid->from, raid->to, ctime(raid->time))});
				else
					raiddescs += ({sprintf("RAID>< %s raided %s on %s", raid->from, raid->to, ctime(raid->time))});
				times += ({raid->time});
			}
		}
		foreach (persist_status->raids; string otherid; mapping allraids) {
			array raids = allraids[(string)id];
			foreach (raids || ({ }), mapping raid)
			{
				if (raid->outgoing)
					raiddescs += ({sprintf("RAID<> %s raided %s on %s", raid->from, raid->to, ctime(raid->time))});
				else
					raiddescs += ({sprintf("RAID<< %s raided %s on %s", raid->from, raid->to, ctime(raid->time))});
				times += ({raid->time});
			}
		}
		sort(times, raiddescs);
		write(raiddescs * "");
		if (!--requests) exit(0);
	})->thencatch(lambda (mixed err) {
		write("Error fetching raids: %s\n", describe_backtrace(err));
		if (!--requests) exit(0);
	});
}

void subpoints_display(string ch) {
	if (!sizeof(persist_status)) persist_status = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_status.json"));
	array scanme = ({ });
	int pagesize = 100;
	mapping cfg;
	array base;
	Concurrent.Future pump(array prev) {
		if (prev) {
			//Deduplicate the results before continuing
			int total = sizeof(prev);
			multiset seen = (<>);
			foreach (prev; int i; mapping sub)
				if (seen[sub->user_id]) prev[i] = 0;
				else seen[sub->user_id] = 1;
			prev -= ({0});
			mapping counts = ([]);
			foreach (prev, mapping sub) counts[sub->tier]++;
			write("Page size %d - %d (%d) subs, %d/%d points\n", pagesize, total, sizeof(prev),
				counts["1000"] + counts["2000"]*2 + counts["3000"]*6, cfg->goal);
			array subs = sprintf("%s at T%1.1s", prev->user_name[*], prev->tier[*]);
			if (base) {
				mapping seen = mkmapping(base, enumerate(sizeof(base)));
				foreach (subs; int i; string s)
					if (!m_delete(seen, s)) //Delete if present
						write("+%d: %s\n", i, s); //Else it's a new one
				write("%{%s\n%}", sprintf("-%d: %s", values(seen)[*], indices(seen)[*]));
			}
			else base = subs;
			--pagesize;
			//if (pagesize > 90) scanme += ({cfg}); //Hack to see more page sizes
		}
		if (!sizeof(scanme)) {if (!--requests) exit(0); return 0;} //All done!
		[cfg, scanme] = Array.shift(scanme);
		return get_helix_paginated("https://api.twitch.tv/helix/subscriptions",
			(["broadcaster_id": cfg->uid, "first": (string)pagesize]),
			(["Authorization": "Bearer " + cfg->token]))->then(pump) {
				//TODO: Report errors but skip any invalid tokens
				//write("%s\n", describe_backtrace(__ARGS__[0]));
				pump(0);
			};
	}
	get_user_id(ch)->then() { [int uid] = __ARGS__;
		foreach (persist_status->subpoints; string nonce; mapping info) {
			if ((int)info->uid != uid) continue;
			scanme += ({info});
		}
		if (!sizeof(scanme)) write("No subpoints tokens for %d\n", uid);
		return pump(0);
	};
}

int main(int argc, array(string) argv)
{
	if (argc == 1)
	{
		Tools.Hilfe.StdinHilfe(({"inherit \"poll.pike\";", "start backend"}));
		return 0;
	}
	requests = argc - 1;
	foreach (argv[1..], string chan)
	{
		if (sscanf(chan, "%s/%s", string ch, string user) && user)
		{
			if (user == "transcoding")
			{
				write("Checking transcoding history...\n");
				//Can't use Helix yet, as it doesn't include the resolutions array
				//request("https://api.twitch.tv/helix/videos?user_id={{USER}}&type=archive&limit=100", ([]), (["username": ch]))
				request("https://api.twitch.tv/kraken/channels/{{USER}}/videos?broadcast_type=archive&limit=100", ([]), (["username": ch]))
					->then(transcoding_display);
				continue;
			}
			if (user == "clips")
			{
				write("Searching for clips...\n");
				clips_display(ch);
				continue;
			}
			if (user == "raids")
			{
				write("Checking raids...\n");
				if (!sizeof(persist_status)) persist_status = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_status.json"));
				raids_display(ch);
				continue;
			}
			if (user == "subpoints") {subpoints_display(ch); continue;}
			write("Checking follow status...\n");
			check_following(user, ch)->then(followinfo_display);
		}
		else
		{
			get_channel_info(chan)->then(chaninfo_display);
		}
	}
	return requests && -1;
}
#endif
