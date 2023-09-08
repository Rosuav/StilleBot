//Has outgrown its original name; now it's most of the Twitch API handling (other than web
//server stuff including webhooks).
inherit hook;
inherit annotated;
@retain: mapping stream_online_since = ([]);
@retain: mapping channel_info = ([]);
@retain: mapping category_names = ([]);
@retain: mapping user_info = ([]);

mapping cached_user_info(int|string user) {
	mapping info = user_info[user];
	if (info && time() - info->_fetch_time < 3600) return info;
}

//Place a request to the API. Returns a Future that will be resolved with a fully
//decoded result (a mapping of Unicode text, generally), or rejects if Twitch or
//the network failed the request.
@export: Concurrent.Future twitch_api_request(Protocols.HTTP.Session.URL url, mapping|void headers, mapping|void options)
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
			if (mapping info = cached_user_info(user)) usernames[tag] = (string)info->id; //Local cache lookup where possible
			else reqs += ({get_user_info(user, "login")
				->then(lambda(mapping info) {replace(usernames, info->login, info->id);})
			});
		}
		if (sizeof(reqs) > 1) reqs = ({Concurrent.all(@reqs)});
		if (sizeof(reqs)) return reqs[0]->then(lambda() {
			return twitch_api_request(replace(url, usernames), headers, options - (<"username">));
		});
		url = replace(url, usernames);
		//If we found everything in cache, carry on with a modified URL.
	}
	string body = options->data;
	if (options->json) {
		headers["Content-Type"] = "application/json";
		body = Standards.JSON.encode(options->json, 1);
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
					return Concurrent.resolve(0)->delay(2)->then(lambda() {return twitch_api_request(url, headers, options);});
				}
				G->G->app_access_token_expiry = -1; //Prevent spinning
				Standards.URI uri = Standards.URI("https://id.twitch.tv/oauth2/token");
				//As below, uri->set_query_variables() doesn't correctly encode query data.
				uri->query = Protocols.HTTP.http_encode_query(([
					"client_id": persist_config["ircsettings"]["clientid"],
					"client_secret": persist_config["ircsettings"]["clientsecret"],
					"grant_type": "client_credentials",
				]));
				return twitch_api_request(uri, ([]), (["method": "POST"]))
					->then(lambda (mapping data) {
						G->G->app_access_token = data->access_token;
						G->G->app_access_token_expiry = time() + data->expires_in - 120;
						//If this becomes a continue function, we could just fall through
						//instead of calling ourselves recursively.
						return twitch_api_request(url, headers, options);
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
	++G->G->twitch_api_query_count;
	return Protocols.HTTP.Promise.do_method(method, url,
			Protocols.HTTP.Promise.Arguments((["headers": headers, "data": body])))
		->then(lambda(Protocols.HTTP.Promise.Result res) {
			int limit = (int)res->headers["ratelimit-limit"],
				left = (int)res->headers["ratelimit-remaining"];
			if (limit) write("Rate limit: %d/%d   \r", limit - left, limit); //Will usually get overwritten
			if (options->return_status) return res->status; //For requests not expected to have a body, but might have multiple success returns
			if (res->status == 204 && res->get() == "") return ([]); //Otherwise, pretend that a 204 response is an empty mapping.
			mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
			if (!mappingp(data)) return Concurrent.reject(({sprintf("%s\nUnparseable response\n%O\n", url, res->get()[..64]), backtrace()}));
			if (data->error && !options->return_errors) return Concurrent.reject(({sprintf("%s\nError from Twitch: %O (%O)\n%O\n", url, data->error, data->status, data), backtrace()}));
			return data;
		});
}

@export: void notice_user_name(string login, string id) {
	//uid_to_name[(string)userid] maps the user names seen to the timestamps.
	//To detect renames, sort the keys and values in parallel; the most recent
	//change is represented by the last two keys.
	if (!login || !persist_status->path) return; //The latter check stops us from bombing in CLI usage
	id = (string)id; login = lower_case((string)login);
	int save = 0;
	mapping u2n = G->G->uid_to_name[id]; if (!u2n) u2n = G->G->uid_to_name[id] = ([]);
	if (!u2n[login]) {u2n[login] = time(); save = 1;}
	//The name-to-UID mapping should be considered advisory, and useful mainly for recent ones.
	mapping n2u = G->G->name_to_uid;
	if (n2u[login] != id) {n2u[login] = id; save = 1;}
	if (save) Stdio.write_file("twitchbot_uids.json", Standards.JSON.encode(({G->G->uid_to_name, G->G->name_to_uid})), 1);
}

//Will return from cache if available. Set type to "login" to look up by name, else uses ID.
@export: Concurrent.Future get_users_info(array(int|string) users, string|void type)
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
		if (mapping info = cached_user_info(u)) results[i] = info;
		else lookups += ({(string)u});
	}
	if (!sizeof(lookups)) return Concurrent.resolve(results); //Got 'em all from cache.
	return get_helix_paginated("https://api.twitch.tv/helix/users", ([type: lookups]))
		->then(lambda(array data) {
			foreach (data, mapping info) {
				info->_fetch_time = time();
				user_info[info->login] = user_info[(int)info->id] = info;
				notice_user_name(info->login, info->id);
			}
			foreach (users; int i; int|string u)
			{
				if (mapping info = cached_user_info(u)) results[i] = info;
				//Note that the returned error will only ever name a single failed lookup.
				//It's entirely possible that others failed too, but it probably won't matter.
				else return Concurrent.reject(({"User not found: " + u + "\n", backtrace()}));
			}
			return results;
		});
}

//As above but only a single user's info. For convenience, 0 will yield 0 without an error.
@export: Concurrent.Future get_user_info(int|string user, string|void type)
{
	return get_users_info(({user}), type)->then(lambda(array(mapping) info) {return sizeof(info) && info[0];});
}

//Convenience shorthand when all you need is the ID
@export: Concurrent.Future get_user_id(string user)
{
	return get_users_info(({user}), "login")->then(lambda(array(mapping) info) {return sizeof(info) && (int)info[0]->id;});
}

//Four related functions to access user credentials.
//Fetch by login or ID, fetch synchronously or asynchronously.
//Async versions are always safe; synchronous depend on cache.
//As of 20230908, tokens are stored by user login, and the ID
//requires a lookup; this will change soon, and then the login
//versions will require the lookup.
//TODO: When this migrates, move token_for_user_id (which will
//then become the fundamental) into globals.pike rather than
//here. The others can all remain here. This will partly break
//encapsulation, but maintain dependency ordering.
@export: array(string) token_for_user_login(string login) {
	login = lower_case(login);
	string token = persist_status->path("bcaster_token")[login];
	if (!token) return ({"", ""});
	return ({token, persist_status->path("bcaster_token_scopes")[login] || ""});
}

//Eventually this will be important, as the synchronous version may fail.
@export: continue Concurrent.Future|array(string) token_for_user_login_async(string login) {
	return token_for_user_login(login);
}

//Not currently reliable; use the async variety for certainty.
@export: array(string) token_for_user_id(int|string userid) {
	mapping info = user_info[(int)userid];
	if (!info) error("Synchronous fetching of tokens by user ID is not yet available\n");
	return token_for_user_login(info->login);
}

@export: continue Concurrent.Future|array(string) token_for_user_id_async(int|string userid) {
	string login = yield(get_user_info((int)userid))->login;
	return token_for_user_login(login);
}

@export: Concurrent.Future get_helix_paginated(string url, mapping|void query, mapping|void headers, mapping|void options, int|void debug)
{
	array data = ({ });
	Standards.URI uri = Standards.URI(url);
	query = (query || ([])) + ([]);
	if (!query->first) query->first = "100"; //Default to the largest page permitted.

	//If any query parameter has more than a hundred entries, most Twitch APIs will
	//reject it. Instead, we hand it the first hundred, and store the rest in overflow.
	//Note that this won't work reliably if MORE than one parameter overflows; you'll
	//see the first hundred of parameter 1 with the first hundred of parameter 2, etc.
	//Any non-overflowing parameters will be correctly replicated on all requests.
	//(If 100 isn't the limit, specify the pagination_limit in options.)
	mapping overflow = ([]);
	int pagination_limit = (options||([]))->pagination_limit || 100;
	foreach (query; string key; mixed val)
		if (arrayp(val) && sizeof(val) > pagination_limit)
			[query[key], overflow[key]] = Array.shift(val / (float)pagination_limit);

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
		//Normal completion: No pagination marker
		if (!raw->pagination || !raw->pagination->cursor
				//Possible Twitch API bug: If the returned cursor is precisely "IA",
				//it's probably the end of the results. It's come up more than once
				//in the past, and might well happen again.
				|| raw->pagination->cursor == "IA"
				//Another possible Twitch bug: Sometimes the cursor is constantly
				//changing, but we get no data each time. In case this happens
				//once by chance, we have a "three strikes and WE'RE out" policy.
				|| (!sizeof(raw->data) && ++empty >= 3)) {
			//If any of that happens, we're done with this block.
			//Were there any array parameters that overflowed?
			if (!sizeof(overflow)) return data;
			//Grab the next block of array parameters. Note that this may theoretically
			//involve more than one parameter, but in practice will usually just be one.
			foreach (indices(overflow), string key) {
				if (sizeof(overflow[key]) == 1)
					//It's the last block (for this key, at least).
					query[key] = m_delete(overflow, key)[0];
				else
					//There are more blocks, so return the rest to the overflow.
					[query[key], overflow[key]] = Array.shift(overflow[key]);
			}
			//Reset pagination, and off we go!
			m_delete(query, "after");
		}
		else query["after"] = raw->pagination->cursor;
		uri->query = Protocols.HTTP.http_encode_query(query);
		return twitch_api_request(uri, headers, options)->then(nextpage);
	}
	return twitch_api_request(uri, headers, options)->then(nextpage);
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

@export: continue Concurrent.Future|array(mapping) get_banned_list(string|int userid, int|void force) {
	if (intp(userid)) userid = (string)userid;
	mapping cached = G_G_("banned_list", userid);
	if (!cached->stale && cached->taken_at > time() - 3600 &&
		(!cached->expires || cached->expires > Calendar.ISO.Second()))
			return cached->banlist;
	string username = yield(get_user_info(userid))->login;
	array creds = yield(token_for_user_login_async(username));
	if (!has_value(creds[1] / " ", "moderation:read")) error("Don't have broadcaster auth to fetch ban list for %O\n", username);
	mapping ret = yield(get_helix_paginated("https://api.twitch.tv/helix/moderation/banned",
		(["broadcaster_id": userid]),
		(["Authorization": "Bearer " + creds[0]]),
	));
	cached->stale = 0; cached->taken_at = time();
	//If any of the entries have expiration times, record the earliest.
	array expires = ret->expires_at - ({""});
	cached->expires = min(@Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", expires[*])); //0 if no expiration
	return cached->banlist = ret;
}

@export: Concurrent.Future complete_redemption(string chan, string rewardid, string redemid, string status) {
	//Fulfil or reject the redemption, consuming or refunding the points
	return get_user_id(chan)->then() {
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions"
				+ "?broadcaster_id=" + __ARGS__[0]
				+ "&reward_id=" + rewardid
				+ "&id=" + redemid,
			(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]),
			(["method": "PATCH", "json": (["status": status])]),
		);
	};
}

//Returns "offline" if not broadcasting, or a channel uptime.
@export: continue Concurrent.Future|string channel_still_broadcasting(string|int chan) {
	if (stringp(chan)) chan = yield(get_user_id(chan));
	array initial = yield(twitch_api_request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1"))->data;
	//If there are no videos found, then presumably the person isn't live, since
	//(even if VODs are disabled) the current livestream always shows up.
	if (!sizeof(initial)) return "offline";
	mixed _ = yield(task_sleep(1.5));
	array second = yield(twitch_api_request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1"))->data;
	//When a channel is offline, the VOD doesn't grow in length.
	if (!sizeof(second) || second[0]->duration == initial[0]->duration) return "offline";
	return second[0]->duration;
}

@export: Concurrent.Future get_channel_info(string name)
{
	return twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id={{USER}}", ([]), (["username": name]))
	->then(lambda(mapping info) {
		info = info->data[0];
		//Provide Kraken-like attribute names for convenience
		//TODO: Find everything that uses the Kraken names and correct them
		info->game = info->game_name;
		info->display_name = info->broadcaster_name;
		info->url = "https://twitch.tv/" + info->broadcaster_login; //Should be reliable, I think?
		info->_id = info->broadcaster_id;
		info->status = info->title;
		if (!channel_info[name]) channel_info[name] = info; //Autocache
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
			if (!channel_info[name]) channel_info[name] = ([ ]);
		}
		else return Concurrent.reject(err);
	});
}

void streaminfo(array data)
{
	//First, quickly remap the array into a lookup mapping
	//This helps us ensure that we look up those we care about, and no others.
	mapping channels = ([]);
	foreach (data, mapping chan) channels[lower_case(chan->user_login)] = chan;
	//Now we check over our own list of channels. Anything absent is assumed offline.
	foreach (list_channel_configs(), mapping cfg) {
		string chan = cfg->login;
		if (chan[0] != '!') stream_status(chan, channels[chan]);
	}
}

continue Concurrent.Future cache_game_names(string game_id)
{
	if (mixed ex = catch {
		array games = yield(get_helix_paginated("https://api.twitch.tv/helix/games/top", (["first":"100"])));
		foreach (games, mapping game) category_names[game->id] = game->name;
		write("Fetched %d games, total %d\n", sizeof(games), sizeof(category_names));
		if (!category_names[game_id]) {
			//We were specifically asked for this game ID. Explicitly ask Twitch for it.
			mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/games?id=" + game_id));
			if (!sizeof(info->data)) werror("Unable to fetch game info for ID %O\n", game_id);
			else if (info->data[0]->id != game_id) werror("???? Asked for game %O but got %O ????\n", game_id, info->data[0]->id);
			else category_names[game_id] = info->data[0]->name;
		}
	}) {
		werror("Error fetching games:\n%s\n", describe_backtrace(ex));
	}
}

//Deprecated, will stop working before long, but isn't needed any more - the API can use new-style tags.
@export: continue Concurrent.Future|array translate_tag_ids(array tag_ids) {return ({ });}

int fetching_game_names = 0;
//Attempt to construct a channel info mapping from the stream info
//May use other caches of information. If unable to build the full
//channel info, returns 0 (recommendation: fetch info via Kraken).
mapping build_channel_info(mapping stream)
{
	mapping ret = ([]);
	ret->game_id = stream->game_id;
	if (!(ret->game = category_names[stream->game_id]))
	{
		if (stream->game_id != "0" && stream->game_id != "" && !fetching_game_names)
		{
			write("Fetching games because we know %d games but not %O\n",
				sizeof(category_names), stream->game_id);
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
	ret->display_name = stream->user_name;
	ret->url = "https://www.twitch.tv/" + lower_case(stream->user_name); //TODO: Get the actual login, which may be different
	ret->status = stream->title;
	ret->online_type = stream->type; //Really, THIS should be called "status" (eg "live"), and "status" should be called Title. But whatevs.
	ret->_id = ret->user_id = stream->user_id;
	//TODO: Keep an eye on the API and see if content classification labels get
	//added to the /stream endpoint (they're only in /channels as of 20230713).
	//This is currently going to be stashing a null into ret.
	ret->content_classification_labels = stream->content_classification_labels;
	ret->_raw = stream; //Avoid using this except for testing
	//Add anything else here that might be of interest
	return ret;
}

continue Concurrent.Future|mapping save_channel_info(string name, mapping info) {
	//Attempt to gather channel info from the stream info. If we
	//can't, we'll get that info via an API call.
	mapping synthesized = build_channel_info(info);
	if (!synthesized) {
		if (info->game_id != "") write("SYNTHESIS FAILED - maybe bad game? %O\n", info->game_id);
		synthesized = yield(get_channel_info(name));
	}
	if (!synthesized->content_classification_labels) {
		//As of 20230713, the /streams endpoint doesn't include CCLs.
		synthesized = yield(get_channel_info(name));
	}
	synthesized->viewer_count = info->viewer_count;
	synthesized->tags = info->tags || ({ });
	synthesized->tag_names = sprintf("[%s]", synthesized->tags[*]) * ", ";
	synthesized->ccls = sprintf("[%s]", synthesized->content_classification_labels[*]) * ", ";
	int changed = 0;
	foreach ("game status tag_names ccls" / " ", string attr)
		changed += synthesized[attr] != channel_info[name][?attr];
	channel_info[name] = synthesized;
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
			"{tag_ids}": "", //Deprecated - use the tag names (new-style tags have no IDs)
			"{ccls}": synthesized->ccls,
		]));
	}
}

@create_hook: constant channel_online = ({"string channel", "int uptime"});
@create_hook: constant channel_offline = ({"string channel", "int uptime"});

//Receive stream status, either polled or by notification
void stream_status(string name, mapping info)
{
	if (!info)
	{
		if (!channel_info[name])
		{
			//Make sure we know about all channels
			write("** Channel %s isn't online - fetching last-known state **\n", name);
			get_channel_info(name);
		}
		else m_delete(channel_info[name], "online_type");
		if (object started = m_delete(stream_online_since, name))
		{
			write("** Channel %s noticed offline at %s **\n", name, Calendar.now()->format_nice());
			object chan = G->G->irc->channels["#"+name];
			runhooks("channel-offline", 0, name);
			int uptime = time() - started->unix_time();
			event_notify("channel_offline", name, uptime);
			if (chan) chan->trigger_special("!channeloffline", ([
				//Synthesize a basic person mapping
				"user": name,
				"displayname": name, //Might not have the actual display name handy (get_channel_info is async)
				"uid": G->G->name_to_uid[name] || "0", //It should always be there, but if someone renames while live, who knows.
			]), ([
				"{uptime}": (string)uptime,
				"{uptime_hms}": describe_time_short(uptime),
				"{uptime_english}": describe_time(uptime),
			]));
			mapping vstat = m_delete(G->G->viewer_stats, name);
			if (sizeof(vstat->half_hour) == 30)
			{
				mapping status = persist_status->path("stream_stats");
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
		if (!stream_online_since[name])
		{
			//Is there a cleaner way to say "convert to local time"?
			object started_here = started->set_timezone(Calendar.now()->timezone());
			write("** Channel %s went online at %s **\n", name, started_here->format_nice());
			object chan = G->G->irc->channels["#"+name];
			runhooks("channel-online", 0, name);
			int uptime = time() - started->unix_time();
			event_notify("channel_online", name, uptime);
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
		stream_online_since[name] = started;
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

//Basically only used after a follow hook; use the same authentication when that switches over.
//Returns an ISO 8601 string, or 0 if not following.
@export: continue Concurrent.Future|string check_following(int userid, int chanid)
{
	array creds = yield(token_for_user_id_async(chanid));
	multiset scopes = (multiset)(creds[1] / " ");
	mapping headers = ([]);
	if (scopes["moderator:read:followers"]) headers->Authorization = "Bearer " + creds[0];
	mapping info = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/channels/followers?broadcaster_id=%d&user_id=%d",
		chanid, userid), headers));
	if (sizeof(info->data)) return info->data[0]->followed_at;
}

//Fetch a stream's schedule, up to N events within the next M seconds.
@export: continue Concurrent.Future|array get_stream_schedule(int|string channel, int rewind, int maxevents, int maxtime) {
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
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id
			+ "&start_time=" + starttime + "&after=" + cursor + "&first=25",
			([]), (["return_errors": 1])));
		if (info->error) break; //Probably 404, schedule not found.
		cursor = info->pagination->?cursor;
		if (!info->data->segments) break; //No segments? Probably no schedule, nothing to return
		foreach (info->data->segments, mapping ev) {
			if (ev->start_time > cutoff) return events;
			events += ({ev});
			if (sizeof(events) >= maxevents) return events;
		}
		if (!cursor) break;
	}
	return events;
}

@export: class EventSub(string hookname, string type, string version, function callback) {
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
		twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([
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
			"return_errors": 1,
		]))
		->then(lambda(mapping ret) {
			if (ret->error && ret->status != 409) //409 ("Conflict") probably just means we're restarting w/o recollection
				werror("EventSub error response - %s=%s\n%O\n", hookname, arg, ret);
		});
	}
}

@create_hook:
constant follower = ({"object channel", "mapping follower"});

//NOTE: This event hook will work only if the broadcaster or a mod has granted permission
//for the "moderator:read:followers" scope. It may be simplest to rely on two checks: either
//the bot account has this permission, or the broadcaster has granted auth; handling the case
//of some other mod granting permission may be tricky.
EventSub new_follower = EventSub("follower", "channel.follow", "2") { [string chan, mapping follower] = __ARGS__;
	notice_user_name(follower->user_login, follower->user_id);
	if (object channel = G->G->irc->channels["#" + chan])
		spawn_task(check_following((int)follower->user_id, channel->userid)) {
			//Sometimes bots will follow-unfollow. Avoid spamming chat with meaningless follow messages.
			if (!__ARGS__[0]) return;
			event_notify("follower", channel, follower);
			channel->trigger_special("!follower", ([
				"user": follower->user_login,
				"displayname": follower->user_name,
			]), ([]));
		};
};
//EventSub raidin = EventSub("raidin", "channel.raid", "1") {Stdio.append_file("evthook.log", sprintf("EVENT: Raid incoming [%d, %O]: %O\n", time(), @__ARGS__));};
EventSub raidout = EventSub("raidout", "channel.raid", "1") {[string chan, mapping info] = __ARGS__;
	object channel = G->G->irc->channels["#" + chan];
	Stdio.append_file("outgoing_raids.log", sprintf("[%s] %s => %s with %d\n",
		Calendar.now()->format_time(), chan, info->to_broadcaster_user_name, (int)info->viewers));
	if (channel) channel->record_raid((int)info->from_broadcaster_user_id, info->from_broadcaster_user_name,
		(int)info->to_broadcaster_user_id, info->to_broadcaster_user_name, 0, (int)info->viewers);
};

void check_hooks(array eventhooks)
{
	foreach (G->G->eventhook_types;; object handler) handler->have_subs = (<>);
	foreach (eventhooks, mapping hook) {
		sscanf(hook->transport->callback || "", "http%*[s]://%*s/junket?%s=%s", string type, string arg);
		object handler = G->G->eventhook_types[type];
		if (!handler) {
			write("Deleting eventhook: %O\n", hook);
			twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions?id=" + hook->id,
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

	foreach (list_channel_configs(), mapping cfg) {
		string chan = cfg->login;
		mapping c = channel_info[chan];
		int userid = c->?_id;
		if (!userid) continue; //We need the user ID for this. If we don't have it, the hook can be retried later. (This also suppresses pseudo-channels.)
		//Seems unnecessary to do all this work every time.
		multiset scopes = (multiset)(token_for_user_login(chan)[1] / " ");
		//TODO: Check if the bot is actually a mod, otherwise use zero.
		string mod = (string)G->G->bot_uid;
		if (scopes["moderator:read:followers"]) mod = userid; //If we have the necessary permission, use the broadcaster's authentication.
		if (mod != "0") new_follower(chan, (["broadcaster_user_id": (string)userid, "moderator_user_id": mod]));
		//raidin(chan, (["to_broadcaster_user_id": (string)userid]));
		raidout(chan, (["from_broadcaster_user_id": (string)userid]));
	}
}

void poll()
{
	G->G->poll_call_out = call_out(poll, 60); //Maybe make the poll interval customizable?
	array chan = list_channel_configs()->login;
	chan = filter(chan) {return __ARGS__[0][?0] != '!';};
	if (!sizeof(chan)) return; //Nothing to check.
	//Prune any "channel online" statuses for channels we don't track any more
	foreach (indices(stream_online_since) - chan, string name) m_delete(stream_online_since, name);
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

protected void create(string|void name)
{
	if (!G->G->uid_to_name) {
		G->G->uid_to_name = ([]);
		G->G->name_to_uid = ([]);
		catch {[G->G->uid_to_name, G->G->name_to_uid] = Standards.JSON.decode(Stdio.read_file("twitchbot_uids.json"));};
		//Migrate UID mappings from persist
		mapping u2n = m_delete(persist_status, "uid_to_name");
		mapping n2u = m_delete(persist_status, "name_to_uid");
		if (u2n && !sizeof(G->G->uid_to_name)) G->G->uid_to_name = u2n;
		if (n2u && !sizeof(G->G->name_to_uid)) G->G->name_to_uid = n2u;
		if (u2n || n2u) {persist_status->save(); Stdio.write_file("twitchbot_uids.json", Standards.JSON.encode(({G->G->uid_to_name, G->G->name_to_uid})), 1);}
	}

	remove_call_out(G->G->poll_call_out);
	#if !constant(INTERACTIVE)
	poll();
	#endif
	::create(name);
}
