//Can be invoked from the command line for tools or interactive API inspection.

//NOTE: The saved stream and channel info are exactly as given by Twitch. Notably,
//all text strings are encoded UTF-8, and must be decoded before use.

void data_available(object q, function cbdata) {cbdata(q->unicode_data());}
void request_ok(object q, function cbdata) {q->async_fetch(data_available, cbdata);}
void request_fail(object q) { } //If a poll request fails, just ignore it and let the next poll pick it up.
void make_request(string url, function cbdata, int|void which_api) //which_api: 1=v5, 2=Helix
{
	if (!which_api) error("Must specify an API - 1=Kraken v5, 2=Helix\n");
	sscanf(persist_config["ircsettings"]["pass"] || "", "oauth:%s", string pass);
	mapping headers = ([]);
	if (which_api == 1) headers["Accept"] = "application/vnd.twitchtv.v5+json";
	if (pass) headers["Authorization"] = "OAuth " + pass;
	//TODO: Use bearer auth where appropriate (is it exclusively when which_api==2?)
	if (string c=persist_config["ircsettings"]["clientid"])
		//Some requests require a Client ID. Not sure which or why.
		headers["Client-ID"] = c;
	Protocols.HTTP.do_async_method("GET", url, 0, headers,
		Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail,cbdata));
}

//Same as make_request but returns a Future instead of using a callback
//TODO: Replace all use of make_request with this (note that this does the JSON decode automatically)
Concurrent.Future request(string url, int|void which_api) //which_api: 1=v5, 2=Helix
{
	if (!which_api) return Concurrent.reject(({"Must specify an API - 1=Kraken v5, 2=Helix\n", backtrace()}));
	sscanf(persist_config["ircsettings"]["pass"] || "", "oauth:%s", string pass);
	mapping headers = ([]);
	if (which_api == 1) headers["Accept"] = "application/vnd.twitchtv.v5+json";
	if (pass) headers["Authorization"] = "OAuth " + pass;
	//TODO: Use bearer auth where appropriate (is it exclusively when which_api==2?)
	if (string c=persist_config["ircsettings"]["clientid"])
		//Some requests require a Client ID. Not sure which or why.
		headers["Client-ID"] = c;
	return Protocols.HTTP.Promise.get_url(url, Protocols.HTTP.Promise.Arguments((["headers": headers])))
		->then(lambda(Protocols.HTTP.Promise.Result res) {
			mixed data = Standards.JSON.decode_utf8(res->get());
			if (!mappingp(data)) return Concurrent.reject(({"Unparseable response\n", backtrace()}));
			if (data->error) return Concurrent.reject(({sprintf("Error from Twitch: %O (%O)\n", data->error, data->status), backtrace()}));
			return data;
		});
}

Concurrent.Future get_user_id(string username)
{
	username = lower_case(username);
	if (int id = G->G->userids[username]) return Concurrent.resolve(id); //Local cache for efficiency
	return request("https://api.twitch.tv/kraken/users?login=" + username, 1)
		->then(lambda(mapping data) {return G->G->userids[username] = (int)data->users[0]->_id;});
}

class get_helix_paginated(string uri, mapping|void query, mapping|void headers)
{
	inherit Concurrent.Promise;
	array data = ({ });

	void create(string|void authtype)
	{
		query = (query || ([])) + ([]); //Get a safe copy for potential mutation
		headers = (headers || ([])) + ([]);
		switch (authtype)
		{
			case "v5": headers["Accept"] = "application/vnd.twitchtv.v5+json"; //fallthrough
			case "oauth":
			{
				sscanf(persist_config["ircsettings"]["pass"] || "", "oauth:%s", string pass);
				if (pass) headers["Authorization"] = "OAuth " + pass;
				break;
			}
			default: break;
		}
		//TODO as above - bearer auth
		if (string c = persist_config["ircsettings"]["clientid"]) headers["Client-ID"] = c;
		send_query();
	}

	void send_query()
	{
		Protocols.HTTP.do_async_method("GET", uri, query, headers,
			Protocols.HTTP.Query()->set_callbacks(request_ok, request_fail, nextpage));
	}

	void nextpage(string resp)
	{
		mixed raw;
		if (catch {raw = Standards.JSON.decode_utf8(resp);}) raw = Standards.JSON.decode(resp); //TODO: Figure out one of these and make sure all callers use it
		if (!mappingp(raw)) {failure(resp); return;}
		if (!raw->data) {failure(raw); return;}
		data += raw->data;
		if (!raw->pagination || !raw->pagination->cursor) {success(data); return;}
		query["after"] = raw->pagination->cursor;
		send_query();
	}
}

//FIXME: The switch to v5 seems to have broken encodings here (see !so sarahburnsstudio).
Concurrent.Future get_channel_info(string name)
{
	return get_user_id(name)->then(lambda(int id) {return request("https://api.twitch.tv/kraken/channels/"+id, 1);})
	->then(lambda(mapping info) {
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
	});
}

Concurrent.Future get_video_info(string name)
{
	return get_user_id(name)->then(lambda(int id) {return
		request("https://api.twitch.tv/kraken/channels/"+id+"/videos?broadcast_type=archive&limit=1", 1);
	})->then(lambda(mapping info) {return info->videos[0];});
}

void streaminfo(array data)
{
	//First, quickly remap the array into a lookup mapping
	//This helps us ensure that we look up those we care about, and no others.
	mapping channels = ([]);
	foreach (data, mapping chan) channels[lower_case(chan->user_name)] = chan; //TODO: Figure out if user_name is login or display name
	//Now we check over our own list of channels. Anything absent is assumed offline.
	foreach (indices(persist_config["channels"]), string chan)
		stream_status(chan, channels[chan]);
}

//TODO maybe: use get_helix_paginated for this
int fetching_game_names = 0;
void gamenames(string data)
{
	mapping info; catch {info = Standards.JSON.decode(data);}; //Some error returns aren't even JSON
	if (!info || info->error) return; //Ignore the 503s and stuff that come back.
	foreach (info->data, mapping game) G->G->category_names[game->id] = game->name;
	write("Fetched %d games, total %d\n", sizeof(info->data), sizeof(G->G->category_names));
	if (!info->pagination || !info->pagination->cursor) {fetching_game_names = 0; write("-- Done!\n");}
	else call_out(cache_game_names, 2, info->pagination->cursor);
}
void cache_game_names(string pag) {make_request("https://api.twitch.tv/helix/games/top?first=100&after=" + pag, gamenames, 2);}

//Attempt to construct a channel info mapping from the stream info
//May use other caches of information. If unable to build the full
//channel info, returns 0 (recommendation: fetch info via Kraken).
mapping build_channel_info(mapping stream)
{
	mapping ret = ([]);
	ret->game_id = stream->game_id;
	if (!(ret->game = G->G->category_names[stream->game_id]))
	{
		if (stream->game_id != "0" && !fetching_game_names)
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
			cache_game_names("");
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
		if (m_delete(G->G->stream_online_since, name))
		{
			write("** Channel %s noticed offline at %s **\n", name, Calendar.now()->format_nice());
			if (object chan = G->G->irc->channels["#"+name])
				chan->save(); //We don't get the offline time, so we'll pretend it was online right up until the time we noticed.
			runhooks("channel-offline", 0, name);
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
		//Attempt to gather channel info from the stream info. If we
		//can't, we'll get that info via Kraken.
		//string last_title = G->G->channel_info[name]?->status; //hack
		mapping synthesized = build_channel_info(info);
		if (synthesized) G->G->channel_info[name] = synthesized;
		else
		{
			write("SYNTHESIS FAILED - maybe bad game? %O\n", info->game_id);
			G->G->channel_info[name] = 0; //Force an update by clearing the old info
			get_channel_info(name);
		}
		//if (synthesized?->status != last_title) write("Old title: %O\nNew title: %O\n", last_title, synthesized?->status); //hack
		//TODO: Report when the game changes?
		object started = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->started_at);
		if (!G->G->stream_online_since[name])
		{
			//Is there a cleaner way to say "convert to local time"?
			object started_here = started->set_timezone(Calendar.now()->timezone());
			write("** Channel %s went online at %s **\n", name, started_here->format_nice());
			if (object chan = G->G->irc->channels["#"+name])
				chan->save(started->unix_time());
			runhooks("channel-online", 0, name);
		}
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
	return Concurrent.all(get_user_id(user), get_user_id(chan))
	->then(lambda(array(int) id) {return request("https://api.twitch.tv/kraken/users/" + id[0] + "/follows/channels/" + id[1], 1);})
	->then(lambda(mapping info) {
		mapping foll = G_G_("participants", chan, user);
		foll->following = "since " + info->created_at;
		return ({user, chan, foll});
	}, lambda(mixed err) {
		if (err[0] == "Error from Twitch: \"Not Found\" (404)") //TODO: Report errors more cleanly
		{
			//Not following. Explicitly store that info.
			mapping foll = G_G_("participants", chan, user);
			foll->following = 0;
			return ({user, chan, foll});
		}
		return ({user, chan, ([])}); //Unknown error. Ignore it (most likely the user will be assumed not to be a follower).
	});
}

void confirm_webhook() {/* There's no data or anything, so nothing to do */}

void create_webhook(string callback, string topic, string secret)
{
	Protocols.HTTP.do_async_method("POST", "https://api.twitch.tv/helix/webhooks/hub", 0,
		([
			"Content-Type": "application/json",
			"Client-Id": persist_config["ircsettings"]["clientid"],
		]),
		Protocols.HTTP.Query()->set_callbacks(request_ok, request_fail, confirm_webhook),
		string_to_utf8(Standards.JSON.encode(([
			"hub.callback": sprintf("%s/junket?%s",
				persist_config["ircsettings"]["http_address"],
				callback,
			),
			"hub.mode": "subscribe",
			"hub.topic": topic,
			"hub.lease_seconds": 864000,
			"hub.secret": secret,
		]))),
	);
}

void webhooks(array data)
{
	multiset(string) follows = (<>), status = (<>);
	if (!G->G->webhook_signer) G->G->webhook_signer = ([]);
	foreach (data, mapping hook)
	{
		int time_left = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", hook->expires_at)->unix_time() - time();
		if (time_left < 300) continue;
		sscanf(hook->callback, "http%*[s]://%*s/junket?%s=%s", string type, string channel);
		if (!G->G->webhook_signer[channel]) continue; //Probably means the bot's been restarted
		if (type == "follow") follows[channel] = 1;
		if (type == "status") status[channel] = 1;
	}
	//write("Already got webhooks for %s\n", indices(watching) * ", ");
	foreach (persist_config["channels"] || ([]); string chan; mapping cfg)
	{
		if (follows[chan] /*&& status[chan]*/) continue; //Already got all hooks
		if (!cfg->allcmds) continue; //Show only for channels we're fully active in
		mapping c = G->G->channel_info[chan];
		int userid = c && c->_id; //For some reason, ?-> is misparsing the data type (???)
		if (!userid) continue; //We need the user ID for this. If we don't have it, the hook can be retried later. (This also suppresses !whisper.)
		string secret = MIME.encode_base64(random_string(15));
		G->G->webhook_signer[chan] = Crypto.SHA256.HMAC(secret);
		write("Creating webhooks for %s\n", chan);
		create_webhook("follow=" + chan, "https://api.twitch.tv/helix/users/follows?first=1&to_id=" + userid, secret);
		//Not currently using this hook. It doesn't actually give us any benefit!
		//create_webhook("status=" + chan, "https://api.twitch.tv/helix/streams?user_id=" + userid, secret);
	}
}

void check_webhooks()
{
	if (!G->G->webhook_lookup_token) return;
	get_helix_paginated("https://api.twitch.tv/helix/webhooks/subscriptions",
		(["first": "100"]),
		(["Authorization": "Bearer " + G->G->webhook_lookup_token]),
	)->on_success(webhooks);
}

void got_lookup_token(string resp)
{
	mixed data = Standards.JSON.decode_utf8(resp); if (!mappingp(data)) return;
	G->G->webhook_lookup_token = data->access_token;
	G->G->webhook_lookup_token_expiry = time() + data->expires_in - 120;
	check_webhooks();
}

void get_lookup_token()
{
	if (!persist_config["ircsettings"]["clientsecret"]) return;
	m_delete(G->G, "webhook_lookup_token");
	G->G->webhook_lookup_token_expiry = time() + 1; //Prevent spinning
	Protocols.HTTP.do_async_method("POST", "https://id.twitch.tv/oauth2/token", ([
		"client_id": persist_config["ircsettings"]["clientid"],
		"client_secret": persist_config["ircsettings"]["clientsecret"],
		"grant_type": "client_credentials",
	]), 0, Protocols.HTTP.Query()->set_callbacks(request_ok, request_fail, got_lookup_token));
}

void poll()
{
	G->G->poll_call_out = call_out(poll, 60); //Maybe make the poll interval customizable?
	array chan = indices(persist_config["channels"] || ({ }));
	if (!sizeof(chan)) return; //Nothing to check.
	//Note: There's a slight TOCTOU here - the list of channel names will be
	//re-checked from persist_config when the response comes in. If there are
	//channels that we get info for and don't need, ignore them; if there are
	//some that we wanted but didn't get, we'll just think they're offline
	//until the next poll.
	get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_login": chan]))
		->on_success(streaminfo);
	string addr = persist_config["ircsettings"]["http_address"];
	if (addr && addr != "")
	{
		if (G->G->webhook_lookup_token_expiry < time()) get_lookup_token();
		else check_webhooks();
	}
}

void report_error(mixed err) {werror(describe_backtrace(err));}

void create()
{
	if (!G->G->stream_online_since) G->G->stream_online_since = ([]);
	if (!G->G->channel_info) G->G->channel_info = ([]);
	if (!G->G->category_names) G->G->category_names = ([]);
	if (!G->G->userids) G->G->userids = ([]);
	remove_call_out(G->G->poll_call_out);
	Concurrent.on_failure(report_error);
	poll();
	add_constant("get_channel_info", get_channel_info);
	add_constant("check_following", check_following);
	add_constant("get_video_info", get_video_info);
	add_constant("stream_status", stream_status);
	add_constant("get_user_id", get_user_id);
}

#if !constant(G)
mapping G = (["G":([])]);
mapping persist_config = (["channels": ({ }), "ircsettings": Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([])]);
mapping persist_status = ([]);
void runhooks(mixed ... args) { }
mapping G_G_(mixed ... args) {return ([]);}

int requests;

mapping decode(string data)
{
	mapping info = Standards.JSON.decode(data);
	if (info && !info->error) return info;
	if (!info) write("Request failed - server down?\n");
	else write("%d %s: %s\n", info->status, info->error, info->message||"(unknown)");
	if (!--requests) exit(0);
}

void interactive(mixed info)
{
	write("%O\n", info);
	//TODO: Surely there's a better way to access the history object for the running Hilfe...
	object history = function_object(all_constants()["backend_thread"]->backtrace()[0]->args[0])->history;
	history->push(info);
}
int req(string url, int|void which_api) //Returns 0 to suppress Hilfe warning.
{
	if (!has_prefix(url, "http")) url = "https://api.twitch.tv/kraken/" + url[url[0]=='/'..];
	request(url, which_api || 1)->then(interactive);
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

void streaminfo_display(mapping info)
{
	if (info->stream)
	{
		object started = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->stream->created_at);
		write("Channel went online at %s\n", started->format_nice());
		write("Uptime: %s\n", describe_time_short(started->distance(Calendar.now())->how_many(Calendar.Second())));
	}
	else write("Channel is offline.\n");
	if (!--requests) exit(0);
}
void chaninfo_display(mapping info)
{
	if (info->mature) write("[MATURE] ");
	write("%s was last seen playing %s, at %s - %s\n",
		info->display_name, string_to_utf8(info->game || "(null)"), info->url, string_to_utf8(info->status || "(null)"));
	if (!--requests) exit(0);
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
	foreach (info->videos, mapping videoinfo)
	{
		mapping res = videoinfo->resolutions;
		if (!res || !sizeof(res)) return; //Shouldn't happen
		string dflt = m_delete(res, "chunked") || "?? unknown res ??"; //Not sure if "chunked" can ever be missing
		write("[%s] %-9s %s - %s\n", videoinfo->created_at, dflt, sizeof(res) ? "TC" : "  ", videoinfo->game);
	}
	if (!--requests) exit(0);
}

class clips_display(string channel)
{
	string dir; multiset unseen;
	void create()
	{
		make_request("https://api.twitch.tv/kraken/clips/top?channel=" + channel + "&period=all&limit=100", this, 1);
		dir = "../clips/" + channel;
		array files = get_dir(dir);
		if (files) unseen = (multiset)glob("*.json", files);
	}
	void `()(string data)
	{
		mapping info = Standards.JSON.decode(data);
		if (info->status == 404 || !info->clips)
		{
			write("Error fetching clips: %O\n", info);
			if (!--requests) exit(0);
			return;
		}
		foreach (info->clips, mapping clip)
		{
			if (unseen)
			{
				unseen[clip->slug + ".json"] = 0;
				Stdio.write_file(dir + "/" + clip->slug + ".json", Standards.JSON.encode(clip, 7));
			}
			write(string_to_utf8(sprintf("[%s] %s %s - %s\n", clip->created_at, clip->slug, clip->curator->display_name, clip->title)));
		}
		if (info->_cursor != "")
		{
			write("Fetching more... %s %O\n", info->_cursor, MIME.decode_base64(info->_cursor));
			make_request("https://api.twitch.tv/kraken/clips/top?channel=" + channel + "&period=all&limit=100&cursor=" + info->_cursor, this, 1);
			return;
		}
		if (unseen && sizeof(unseen))
			write("%d deleted clips:\n%{\t%s\n%}", sizeof(unseen), sort((array)unseen));
		if (!--requests) exit(0);
	}
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
				get_user_id(ch)->then(lambda(int id) {return
					request("https://api.twitch.tv/kraken/channels/" + id + "/videos?broadcast_type=archive&limit=100", 1);
				})->then(transcoding_display);
				continue;
			}
			if (user == "clips")
			{
				write("Searching for clips...\n");
				clips_display(ch);
				continue;
			}
			write("Checking follow status...\n");
			check_following(user, ch)->then(followinfo_display);
		}
		else
		{
			//For online channels, we could save ourselves one request. Simpler to just do 'em all though.
			++requests; //These require two requests
			get_channel_info(chan)->then(chaninfo_display)
				->then(lambda() {return request("https://api.twitch.tv/helix/streams?user_login=" + chan, 2);})
				->then(streaminfo_display);
		}
	}
	return requests && -1;
}
#endif
