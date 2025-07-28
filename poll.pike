//Has outgrown its original name; now it's most of the Twitch API handling (other than web
//server stuff including webhooks).
inherit hook;
inherit annotated;
@retain: mapping stream_online_since = ([]);
@retain: mapping category_names = ([]);
@retain: mapping user_info = ([]);

mapping cached_user_info(int|string user) {
	mapping info = user_info[user];
	if (info && time() - info->_fetch_time < 3600) return info;
}

__async__ void get_credentials() {
	//TODO: Wait properly, don't just sleep
	while (!G->G->dbsettings->credentials) await(task_sleep(1));
}

//Place a request to the API. Returns a Future that will be resolved with a fully
//decoded result (a mapping of Unicode text, generally), or rejects if Twitch or
//the network failed the request.
@export: __async__ mapping|int twitch_api_request(Protocols.HTTP.Session.URL url, mapping|void headers, mapping|void options) {
	G->G->serverstatus_statistics->api_request_count++;
	if (!G->G->dbsettings->credentials) await(get_credentials());
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
		if (sizeof(reqs)) await(reqs[0]); //Populate the cache. TODO: Tidy it up, don't use then().
		url = replace(url, usernames);
		//Carry on with a modified URL.
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
				if (!G->G->instance_config->clientsecret) error("%s\nUnable to use app auth without a client secret\n", url);
				if (G->G->app_access_token_expiry == -1) {
					//TODO: Wait until the other request returns.
					//For now we just sleep and try again.
					while (G->G->app_access_token_expiry == -1) sleep(2);
				} else {
					G->G->app_access_token_expiry = -1; //Prevent spinning
					Standards.URI uri = Standards.URI("https://id.twitch.tv/oauth2/token");
					//As below, uri->set_query_variables() doesn't correctly encode query data.
					uri->query = Protocols.HTTP.http_encode_query(([
						"client_id": G->G->instance_config->clientid,
						"client_secret": G->G->instance_config->clientsecret,
						"grant_type": "client_credentials",
					]));
					mapping data = await(twitch_api_request(uri, ([]), (["method": "POST"])));
					G->G->app_access_token = data->access_token;
					G->G->app_access_token_expiry = time() + data->expires_in - 120;
				}
			}
			headers->Authorization = "Bearer " + G->G->app_access_token;
		}
		else {
			//Under what circumstances do we need to use "OAuth <token>" instead?
			//In Mustard Mine, the only remaining place is PUT /kraken/channels which we
			//don't use here, but are there any others?
			//20200511: It seems emote lookups require "OAuth" instead of "Bearer". Sheesh.
			headers["Authorization"] = (options->authtype || "Bearer") + " " + G->G->dbsettings->credentials->token;
		}
	} else if (intp(headers["Authorization"])) {
		//Simplify a common case
		mapping cred = G->G->user_credentials[headers["Authorization"]];
		if (!cred) error("%s\nNo authorization for %O\n", url, headers["Authorization"]);
		headers["Authorization"] = "Bearer " + cred->token;
	}
	if (string c = !headers["Client-ID"] && G->G->instance_config->clientid)
		//Most requests require a Client ID. Not sure which don't, so just provide it (if not already set).
		headers["Client-ID"] = c;
	++G->G->twitch_api_query_count;
	Protocols.HTTP.Promise.Result res = await(Protocols.HTTP.Promise.do_method(method, url,
			Protocols.HTTP.Promise.Arguments((["headers": headers, "data": body]))));
	int limit = (int)res->headers["ratelimit-limit"],
		left = (int)res->headers["ratelimit-remaining"];
	#if !constant(HEADLESS)
	if (limit) write("Rate limit: %d/%d   \r", limit - left, limit); //Will usually get overwritten
	#endif
	if (options->return_status) return res->status; //For requests not expected to have a body, but might have multiple success returns
	if (res->status == 204 && res->get() == "") return ([]); //Otherwise, pretend that a 204 response is an empty mapping.
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	if (!mappingp(data)) error("%s\nUnparseable response\n%O\n", url, res->get()[..64]);
	if (data->error && !options->return_errors) error("%s\nError from Twitch: %O (%O)\n%O\n", url, data->error, data->status, data);
	return data;
}

@retain: mapping recent_user_sightings = ([]); //Map a user ID (int) to a login
@export: void notice_user_name(string login, string|int id) {
	if (!login) return;
	string bot = G->G->instance_config->local_address; if (!bot) return;
	if (recent_user_sightings[(int)id] == login) return;
	recent_user_sightings[(int)id] = login;
	G->G->DB->save_sql("insert into stillebot.user_login_sightings (twitchid, login, bot) values (:id, :login, :bot) on conflict do nothing",
		(["id": id, "login": lower_case(login), "bot": bot]));
}

@export: __async__ array(mapping) get_helix_paginated(string url, mapping|void query, mapping|void headers, mapping|void options, int|void debug)
{
	if (!G->G->dbsettings->credentials) await(get_credentials());
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
	while (1) {
		mapping raw = await(twitch_api_request(uri, headers, options));
		if (!raw->data) error("Unparseable response\n%O\n", indices(raw));
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
	}
}

//Will return from cache if available. Set type to "login" to look up by name, else uses ID.
@export: __async__ array(mapping)|zero get_users_info(array(int|string) users, string|void type) {
	//Simplify things elsewhere: 0 yields 0 with no error. (Otherwise you'll
	//always get an array of mappings, or a rejection.)
	if (!users) return 0;
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
	if (!sizeof(lookups)) return results; //Got 'em all from cache.
	array data = await(get_helix_paginated("https://api.twitch.tv/helix/users", ([type: lookups])));
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
		else error("User not found: " + u + "\n");
	}
	return results;
}

//As above but only a single user's info. For convenience, 0 will yield 0 without an error.
@export: __async__ mapping|zero get_user_info(int|string user, string|void type) {
	array(mapping) info = await(get_users_info(({user}), type));
	return sizeof(info) && info[0];
}

//Convenience shorthand when all you need is the ID
@export: __async__ int get_user_id(string user) {
	array(mapping) info = await(get_users_info(({user}), "login"));
	return sizeof(info) && (int)info[0]->id;
}

//This isn't currently spawned anywhere. Should it be? What if auth fails?
__async__ void check_bcaster_tokens() {
	foreach (G->G->user_credentials; string|int chan; mapping cred) {
		if (stringp(chan)) continue; //Don't need to check both username and userid
		mixed resp = await(twitch_api_request("https://id.twitch.tv/oauth2/validate",
			(["Authorization": "Bearer " + cred->token])));
		array scopes = sort(resp->scopes || ({ }));
		if (cred->scopes * " " != scopes * " ") cred->scopes = scopes;
		cred->validated = time();
		G->G->DB->save_user_credentials(cred);
	}
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

@export: __async__ array get_banned_list(string|int userid, int|void force) {
	if (intp(userid)) userid = (string)userid;
	mapping cached = G_G_("banned_list", userid);
	if (!cached->stale && cached->taken_at > time() - 3600 &&
		(!cached->expires || cached->expires > Calendar.ISO.Second()))
			return cached->banlist;
	string username = await(get_user_info(userid))->login;
	array(string) creds = token_for_user_login(username);
	if (!has_value(creds[1] / " ", "moderation:read")) error("Don't have broadcaster auth to fetch ban list for %O\n", username);
	array(mapping) ret = await(get_helix_paginated("https://api.twitch.tv/helix/moderation/banned",
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
	array(string) creds = token_for_user_login(chan);
	return get_user_id(chan)->then() {
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions"
				+ "?broadcaster_id=" + __ARGS__[0]
				+ "&reward_id=" + rewardid
				+ "&id=" + redemid,
			(["Authorization": "Bearer " + creds[0]]),
			(["method": "PATCH", "json": (["status": status])]),
		);
	};
}

//Returns "offline" if not broadcasting, or a channel uptime.
@export: __async__ string channel_still_broadcasting(string|int chan) {
	if (stringp(chan)) chan = await(get_user_id(chan));
	array initial = await(twitch_api_request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1"))->data;
	//If there are no videos found, then presumably the person isn't live, since
	//(even if VODs are disabled) the current livestream always shows up.
	if (!sizeof(initial)) return "offline";
	await(task_sleep(1.5));
	array second = await(twitch_api_request("https://api.twitch.tv/helix/videos?type=archive&user_id=" + chan + "&first=1"))->data;
	//When a channel is offline, the VOD doesn't grow in length.
	if (!sizeof(second) || second[0]->duration == initial[0]->duration) return "offline";
	return second[0]->duration;
}

@export: Concurrent.Future get_channel_info(string name) { //Get info based on a user NAME, not ID, eg for shoutouts
	return twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id={{USER}}", ([]), (["username": name]))
	->then(lambda(mapping info) {
		info = info->data[0];
		info->game = info->game_name;
		info->url = "https://twitch.tv/" + info->broadcaster_login; //Should be reliable, I think?
		return info;
	}, lambda(mixed err) {
		if (has_prefix(err[0], "User not found: ")) werror(err[0]); //Should probably become a channel error message if it came from a !so
		else return Concurrent.reject(err);
	});
}

constant channelonline = special_trigger("!channelonline", "The channel has recently gone online (started streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english", "Status");
constant channelsetup = special_trigger("!channelsetup", "The channel has changed its category/title/CCLs", "The broadcaster", "category, title, tag_names, ccls", "Status");
constant channeloffline = special_trigger("!channeloffline", "The channel has recently gone offline (stopped streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english", "Status");

void streaminfo(array data)
{
	//First, quickly remap the array into a lookup mapping
	//This helps us ensure that we look up those we care about, and no others.
	mapping channels = ([]);
	foreach (data, mapping chan) channels[(int)chan->user_id] = chan;
	//Now we check over our own list of channels. Anything absent is assumed offline.
	foreach (values(G->G->irc->id), object channel) if (channel->userid) {
		if (mapping info = channels[channel->userid]) {
			object started = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->started_at);
			if (!stream_online_since[channel->userid]) {
				//Is there a cleaner way to say "convert to local time"?
				object started_here = started->set_timezone(Calendar.now()->timezone());
				write("** Channel %s went online at %s **\n", channel->login, started_here->format_nice());
				int uptime = time() - started->unix_time();
				event_notify("channel_online", channel->login, uptime, channel->userid);
				channel->trigger_special("!channelonline", ([
					//Synthesize a basic person mapping
					"user": channel->login,
					"displayname": info->user_name,
					"uid": (string)info->user_id,
				]), ([
					"{uptime}": (string)uptime,
					"{uptime_hms}": describe_time_short(uptime),
					"{uptime_english}": describe_time(uptime),
				]));
			}
			stream_online_since[channel->userid] = started;
		} else { //If the channel's offline, we have no status info (since it returns data only for those online).
			if (object started = m_delete(stream_online_since, channel->userid)) {
				write("** Channel %s noticed offline at %s **\n", channel->login, Calendar.now()->format_nice());
				int uptime = time() - started->unix_time();
				event_notify("channel_offline", channel->login, uptime, channel->userid);
				channel->trigger_special("!channeloffline", ([
					//Synthesize a basic person mapping
					"user": channel->login,
					"displayname": channel->display_name,
					"uid": (string)channel->userid,
				]), ([
					"{uptime}": (string)uptime,
					"{uptime_hms}": describe_time_short(uptime),
					"{uptime_english}": describe_time(uptime),
				]));
			}
		}
	}
}

@EventNotify("channel.update=2"): __async__ void channel_setup_changed(object channel, mapping info) {
	//As of 20240401, this notification does not include stream tags. Even worse, there's a
	//short time delay during which the OLD tags are returned by the API. So we lag out by
	//a bit, *then* query the tags. Can eliminate both if the notification grows tags.
	sleep(0.5);
	mapping chaninfo = await(get_channel_info(info->broadcaster_user_name));
	channel->trigger_special("!channelsetup", ([
		//Synthesize a basic person mapping
		"user": info->broadcaster_user_login,
		"displayname": info->broadcaster_user_name,
		"uid": info->broadcaster_user_id,
	]), ([
		"{category}": info->category_name,
		"{title}": info->title,
		"{tag_names}": sprintf("[%s]", chaninfo->tags[*]) * ", ",
		"{ccls}": sprintf("[%s]", info->content_classification_labels[*]) * ", ",
	]));
}

//The regrettable order of parameters is due to channelids being added later.
//NOTE: These hooks may be called on a non-active bot. Check for this if it matters to you.
@create_hook: constant channel_online = ({"string channelname", "int uptime", "int channelid"});
@create_hook: constant channel_offline = ({"string channelname", "int uptime", "int channelid"});

//Basically only used after a follow hook; use the same authentication when that switches over.
//Returns an ISO 8601 string, or 0 if not following.
@export: __async__ string check_following(int userid, int chanid)
{
	array creds = token_for_user_id(chanid);
	multiset scopes = (multiset)(creds[1] / " ");
	mapping headers = ([]);
	if (scopes["moderator:read:followers"]) headers->Authorization = "Bearer " + creds[0];
	mixed ex = catch {
		mapping info = await(twitch_api_request(sprintf(
			"https://api.twitch.tv/helix/channels/followers?broadcaster_id=%d&user_id=%d",
			chanid, userid), headers));
		if (sizeof(info->data)) return info->data[0]->followed_at;
	};
	if (ex) {
		werror("ERROR IN check_following(%O, %O)\n", userid, chanid);
		if (headers->Authorization) werror("Using broadcaster auth\n");
		werror(describe_backtrace(ex));
	}
}

//Fetch a stream's schedule, up to N events within the next M seconds.
@export: __async__ array get_stream_schedule(int|string channel, int rewind, int maxevents, int maxtime) {
	int id = (int)channel || await(get_user_id(channel));
	if (!id) return ({ });
	//NOTE: Do not use get_helix_paginated here as the events probably go on forever.
	array events = ({ });
	string cursor = "";
	object begin = Calendar.ISO.Second()->set_timezone("UTC")->add(-rewind);
	string starttime = begin->format_ymd() + "T" + begin->format_tod() + "Z";
	object limit = Calendar.ISO.Second()->set_timezone("UTC")->add(maxtime);
	string cutoff = limit->format_ymd() + "T" + limit->format_tod() + "Z";
	while (1) {
		mapping info = await(twitch_api_request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id
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

@retain: mapping twitch_category_cache = ([]);
@export: __async__ string get_category_id(string name) {
	//Cached for performance. It's highly likely this will be called with known categories.
	if (string id = twitch_category_cache[name]) return id;
	array ret = await(twitch_api_request("https://api.twitch.tv/helix/games?name=" + Protocols.HTTP.uri_encode(name)))->data;
	return twitch_category_cache[name] = (ret && sizeof(ret) && ret[0]->id) || "";
}

@create_hook:
constant follower = ({"object channel", "mapping follower"});
constant new_follower = special_trigger("!follower", "Someone follows the channel", "The new follower", "", "Stream support");

//NOTE: This event hook will work only if the broadcaster or a mod has granted permission
//for the "moderator:read:followers" scope. It may be simplest to rely on two checks: either
//the bot account has this permission, or the broadcaster has granted auth; handling the case
//of some other mod granting permission may be tricky.
@EventNotify("channel.follow=2"):
void got_follower(object channel, mapping follower) {
	notice_user_name(follower->user_login, follower->user_id);
	if (channel)
		check_following((int)follower->user_id, channel->userid)->then() {
			//Sometimes bots will follow-unfollow. Avoid spamming chat with meaningless follow messages.
			if (!__ARGS__[0]) return;
			event_notify("follower", channel, follower);
			channel->trigger_special("!follower", ([
				"user": follower->user_login,
				"displayname": follower->user_name,
			]), ([]));
		};
};

@EventNotify("channel.raid=1"):
void raidout(object _, mapping info) {
	object channel = G->G->irc->id[(int)info->from_broadcaster_user_id]; if (!channel) return;
	Stdio.append_file("outgoing_raids.log", sprintf("[%s] %s => %s with %d\n",
		Calendar.now()->format_time(), string_to_utf8(info->from_broadcaster_user_name), string_to_utf8(info->to_broadcaster_user_name), (int)info->viewers));
	channel->record_raid((int)info->from_broadcaster_user_id, info->from_broadcaster_user_name,
		(int)info->to_broadcaster_user_id, info->to_broadcaster_user_name, 0, (int)info->viewers);
}

void check_hooks(array eventhooks)
{
	multiset(string) have_conduitbroken = (<>);
	foreach (eventhooks, mapping hook) {
		if (hook->transport->method == "conduit") {
			string type = hook->type + "=" + hook->version;
			if (!G->G->eventhooks[type]) {
				write("Deleting conduit eventhook: %O\n", hook);
				twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions?id=" + hook->id,
					([]), (["method": "DELETE", "authtype": "app", "return_status": 1]));
			} else {
				foreach (({"", "from_", "to_"}), string pfx)
					if (hook->condition[pfx + "broadcaster_user_id"])
						G_G_("eventhooks", type, "")[pfx + hook->condition[pfx + "broadcaster_user_id"]] = 1;
			}
			continue;
		}
		//Otherwise it's a webhook event. There is only one of these, and it's conduitbroken; which means
		//we need to establish it if we don't yet have it.
		sscanf(hook->transport->callback || "h", "http%*[s]://%s/junket?%s=", string addr, string type);
		if (type != "conduitbroken") {
			write("Deleting eventhook: %O\n", hook);
			twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions?id=" + hook->id,
				([]), (["method": "DELETE", "authtype": "app", "return_status": 1]));
		}
		else have_conduitbroken[addr] = 1;
	}

	foreach (values(G->G->irc->id), object channel) {
		int userid = channel->userid;
		if (!userid) continue; //Ignore the demo
		//Seems unnecessary to do all this work every time.
		multiset scopes = (multiset)(token_for_user_id(userid)[1] / " ");
		//TODO: Check if the bot is actually a mod and use that permission
		if (scopes["moderator:read:followers"]) //If we have the necessary permission, use the broadcaster's authentication.
			G->G->establish_hook_notification(userid, "channel.follow=2", (["broadcaster_user_id": (string)userid, "moderator_user_id": (string)userid]));
		G->G->establish_hook_notification(userid, "channel.update=2", (["broadcaster_user_id": (string)userid]));
		G->G->establish_hook_notification("from_" + userid, "channel.raid=1", (["from_broadcaster_user_id": (string)userid]));
		G->G->establish_hook_notification("to_" + userid, "channel.raid=1", (["to_broadcaster_user_id": (string)userid]));
	}

	//If we don't have a conduitbroken eventhook for our local address, establish one.
	if (!have_conduitbroken[G->G->instance_config->local_address]) {
		string secret = MIME.encode_base64(random_string(15));
		G->G->DB->mutate_config(0, "eventhook_secret") {
			//Save the secret. This is unencrypted and potentially could be leaked.
			//The attack surface is fairly small, though - at worst, an attacker
			//could forge a notification from Twitch, causing us to switch which
			//bot is primary. And to do that, you'd need access to the database.
			__ARGS__[0][G->G->instance_config->local_address] = secret;
		};
		twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([
			"authtype": "app",
			"json": ([
				"type": "conduit.shard.disabled", "version": "1", //As of 20240324, the docs say it should be version "beta", but "1" seems to be what works
				"condition": (["client_id": G->G->instance_config->clientid]),
				"transport": ([
					"method": "webhook",
					"callback": sprintf("https://%s/junket?conduitbroken=1",
						G->G->instance_config->local_address),
					"secret": secret,
				]),
			]),
		]));
	}
}

void poll()
{
	G->G->poll_call_out = call_out(poll, 60); //Maybe make the poll interval customizable?
	array chan = indices(G->G->irc->?id || ([]));
	chan = filter(chan) {return __ARGS__[0];}; //Exclude !demo which has a userid of 0
	if (!sizeof(chan)) return; //Nothing to check.
	//Prune any "channel online" statuses for channels we don't track any more
	foreach (indices(stream_online_since) - chan, int id) m_delete(stream_online_since, id);
	//Note: There's a slight TOCTOU here - the list of channel IDs will be
	//re-checked from saved configs when the response comes in. If there are
	//channels that we get info for and don't need, ignore them; if there are
	//some that we wanted but didn't get, we'll just think they're offline
	//until the next poll.
	get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_id": (array(string))chan, "first": "100"]))
		->on_success(streaminfo);
	//There has been an issue with failures and a rate limiting from Twitch.
	//I suspect that something is automatically retrying AND the sixty-sec
	//poll is triggering again, causing stacking requests. Look into it if
	//possible. Otherwise, there'll be a bit of outage (cooldown) any time
	//I hit this sort of problem.
}

int(1bit) is_active; //Last-known active state
@hook_database_settings: void poll_only_when_active(mapping settings) {
	int now_active = is_active_bot();
	if (now_active == is_active) return;
	is_active = now_active;
	#if !constant(INTERACTIVE)
	if (is_active) poll();
	#endif
}

protected void create(string|void name)
{
	is_active = is_active_bot();
	remove_call_out(G->G->poll_call_out);
	#if !constant(INTERACTIVE)
	poll();
	//TODO: Check this periodically. No need to hammer this every 60 seconds, but more than just on code reload would be good.
	string addr = G->G->instance_config->http_address;
	if (addr && addr != "")
		get_helix_paginated("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([]), (["authtype": "app"]))
			->on_success(check_hooks);
	#endif
	::create(name);
}
