inherit annotated;
inherit http_websocket;

constant markdown = #"# Synchronize Google and Twitch calendars

<section id=synchronization></section>

[Log in with Google](:#googleoauth) to select from your calendars.
{:#googlestatus}

<section id=calendarlist></section>

<section id=calendar></section>
";

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"content-type", "x-goog-resource-id", "x-goog-channel-expiration">);
		werror("Forwarding calendar webhook...\n");
		Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
			Protocols.HTTP.Promise.Arguments((["headers": req->request_headers & headers, "data": req->body_raw])));
		//As elsewhere, not currently awaiting the promise. Should we?
		return "Passing it along.";
	}
	//TODO: Handle webhooks, notably updating the Twitch schedule any time the calendar changes
	if (string calid = req->request_type == "POST" && req->request_headers["x-goog-resource-id"]) {
		//TODO: What is x-goog-channel-expiration and how do we extend it? It starts out just one week ahead.
		werror("CALENDAR WEBHOOK %O\nHeaders %O\nBody: %O\n", req->misc->channel, req->request_headers, req->body_raw);
		string resource = req->request_headers["x-goog-resource-id"];
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "calendar"));
		if (resource != cfg->gcal_resource_id) {
			//TODO: Delete the old and unneeded webhook; this signal came from a calendar
			//that we're no longer synchronizing with.
			return "Ehh whatever, thanks anyway";
		}
		//Note that the webhook doesn't actually say what changed, just that a change happened.
		//So the easiest thing here will be to trigger a full resync as soon as any change occurs.
		synchronize(req->misc->channel->userid);
		return "Okay.";
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

__async__ mapping google_api(string url, string auth, mapping params) {
	if (!params->headers) params->headers = ([]);
	if (auth == "apikey") params->headers["X-goog-api-key"] = await(G->G->DB->load_config(0, "googlecredentials"))->calendar;
	else params->headers->Authorization = "Bearer " + auth;
	if (params->json) {
		params->data = Standards.JSON.encode(m_delete(params, "json"), 1);
		params->headers["Content-Type"] = "application/json; charset=utf-8";
	}
	object res = await(Protocols.HTTP.Promise.do_method(
		params->data ? "POST" : "GET",
		"https://www.googleapis.com/" + url,
		Protocols.HTTP.Promise.Arguments(params),
	));
	//TODO: If not HTTP 200, throw.
	return Standards.JSON.decode_utf8(res->get());
}

@retain: mapping synchronization_cache = ([]);

@retain: mapping calendar_cache = ([]);
__async__ void fetch_calendar_info(int userid) {
	mapping cfg = await(G->G->DB->load_config(userid, "calendar"));
	if (!cfg->oauth->?access_token) return;
	mapping resp = await(google_api("calendar/v3/users/me/calendarList", cfg->oauth->?access_token, ([])));
	if (resp->error->?status == "UNAUTHENTICATED") {
		//Since you seem to have lost auth, clear the oauth. This may or may not be ideal, but
		//it's probably easier than messing with refresh tokens. In fact, we may not even need
		//to bother storing ANY credentials in persistent storage, and just use them for the
		//session; once a calendar has been activated and the watch begun, everything can be
		//done with the API key.
		await(G->G->DB->mutate_config(userid, "calendar") {m_delete(__ARGS__[0]->oauth, "access_token");});
		calendar_cache[cfg->google_id] = ([
			"expires": 0, //Don't cache this, re-fetch as soon as we have credentials.
			"calendars": ({ }),
		]);
	}
	else calendar_cache[cfg->google_id] = ([
		"expires": time() + 300, //Fairly conservative expiration here, it'd be fine longer if we had an explicit refresh action
		"calendars": resp->items,
	]);
	send_updates_all("#" + userid);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "calendar"));
	mapping cals = calendar_cache[cfg->google_id];
	if (cals->?expires < time()) fetch_calendar_info(channel->userid);
	return ([
		"google_id": cfg->google_id || "",
		"google_name": cfg->google_name || "",
		"google_profile_pic": cfg->google_profile_pic || "",
		"have_credentials": !!cfg->oauth->?access_token,
		"calendars": cals->?calendars || ({ }),
		"synchronized_calendar": cfg->gcal_calendar_name,
		"synchronized_calendar_timezone": cfg->gcal_time_zone,
		"sync": synchronization_cache[channel->userid] || ([]),
	]);
}

__async__ void synchronize(int userid) {
	mapping cfg = await(G->G->DB->load_config(userid, "calendar"));
	//TODO: If the token has expired, refresh it. Or maybe do that inside google_api?
	//werror("Token expires in %d seconds.\n", cfg->oauth->expires - time());
	//This isn't entirely correct. It seems that the token only expires after a period
	//of inactivity?? While I'm actively testing things, the token remains valid.
	//Test this again after a day or two of quietness, and see what we need to do.

	//Updating your Twitch schedule from your Google calendar is done in two parts: Weekly
	//and non-weekly events. Twitch doesn't have recurrence rules for anything other than
	//weekly, so if your Gcal specifies "every second Tuesday" or "first Thursday of the
	//month" or something, we will turn those into individual (non-recurring) events.
	//This means we need four pieces of information:
	//1) Google recurring events
	//2) Google non-recurring events
	//3) Twitch weekly events
	//4) Twitch single events
	mapping timespan = ([
		"timeMin": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time())),
		"timeMax": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time() + 604800 * 4)), //Give us four weeks' worth of events
	]);
	//Using singleEvents: true makes it much easier to query the current schedule, as without this
	//the events are given at the time that the recurrence began (maybe years ago). But we don't get
	//the actual recurrence rule this way. Thus, we fetch BOTH ways, recording the IDs of all of the
	//recurring events and their recurrence rules.
	mapping recurring = await(google_api("calendar/v3/calendars/" + cfg->gcal_sync + "/events", "apikey", ([
		"variables": timespan,
	])));
	mapping recurrence_rule = ([]);
	foreach (recurring->items || ({ }), mapping ev) catch {
		string rr = ev->recurrence[0]; //If it's absent or empty, bail.
		//For now, a very strict and simplistic way to recognize recurring events.
		//TODO: What happens if you delete one instance of a recurring event? We need to cancel
		//the corresponding slot in Twitch, but ideally, we want to retain the record that it's
		//a weekly event.
		if (has_prefix(rr, "RRULE:FREQ=WEEKLY;")) recurrence_rule[ev->id] = rr;
	};

	//Query the current Twitch schedule. Twitch (currently) does not allow you to update the start time
	//for a recurring event, and I don't think there's a way to cancel just one instance. So if you move
	//one instance of a recurrer, we'll have to create that one as a one-off, and probably cancel the old
	//recurrer and create a brand new one starting the following week? I think?? Incidentally, one-offs
	//are only available to affiliates and partners. Not sure why, but it's something I'll have to test,
	//probably on the Mustard Mine's account.
	array twitch = await(get_stream_schedule(userid, 0, 1000, 604800 * 4));
	//werror("Twitch schedule %O\n", twitch);
	mapping existing_schedule = ([]);
	foreach (twitch, mapping ev) {
		//NOTE: ev->id is probably meant to be opaque, but it's the only way to recognize which
		//ones are from the same recurring event. It's base 64 JSON and contains a segmentID that
		//is the same for all instances of the same recurring event.

		//Twitch gives us UTC start times eg "2025-01-19T23:00:00Z", but Google gives us local
		//start times eg "2025-01-20T10:00:00+11:00". Convert both into time_t.
		int start = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", ev->start_time)->unix_time();
		ev->time_t = start;

		//werror("Twitch schedule %O id %s\n", ev->start_time, MIME.decode_base64(ev->id));
		existing_schedule[start] = ev;
		//ev->category->id, ev->title, ev->end_time, ev->is_recurring
		//Note that Twitch won't let us update the end_time directly; instead we update the duration,
		//so we'll need to do the arithmetic. But we should be able to compare end_time to endTime.
	}

	//XKCD 713: Meet hot singles in your calendar today!
	mapping singles = await(google_api("calendar/v3/calendars/" + cfg->gcal_sync + "/events", "apikey", ([
		"variables": timespan | (["singleEvents": "true", "orderBy": "startTime"]),
	])));
	array events = singles->items || ({ });
	mapping timeslots = ([]);
	foreach (events, mapping ev) {
		string|zero rr = recurrence_rule[ev->recurringEventId];
		//Note that we assume that an event starts and ends in the same timezone (eg Australia/Melbourne).
		//Twitch only allows one timezone per event anyway.
		int start = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", ev->start->dateTime)->unix_time(); //Can't shortcut by comparing the text strings as these ones are in local time
		ev->time_t = start;
		mapping tw = m_delete(existing_schedule, start);
		//For now, assume that once we've seen one event from a recurring set, we've seen 'em all.
		//TODO: Handle single-instance deletion or moving of an event.
		string action = "OK"; //No action needed
		if (!tw) action = "New";
		//TODO: See if the event fully matches; if it doesn't, action = "Update"
		timeslots[start] = ([
			"action": action,
			"time_t": start,
			"twitch": tw,
			"google": ev,
		]);
		if (rr == "*Done*") continue;
		werror("%s EVENT %O->%O %O %O %s\n", tw ? "EXISTING" : "NEW", ev->start->dateTime, ev->end->dateTime, ev->start->timeZone, rr, ev->summary);
		//TODO: If "Category: ...." is in ev->description, set the category_id for the Twitch event
		if (rr) recurrence_rule[ev->recurringEventId] = "*Done*";
	}
	foreach (existing_schedule; int start; mapping tw) timeslots[start] = ([
		"action": "Delete",
		"time_t": start,
		"twitch": tw,
		"google": 0,
	]);
	//Guarantee that events are sorted by timestamp
	sort(events->time_t, events);
	sort(twitch->time_t, twitch);
	array paired_events = values(timeslots); sort(indices(timeslots), paired_events);
	synchronization_cache[userid] = ([
		"expires": time() + 3600,
		"synctime": ctime(time()), //TODO format on front end, can't be bothered now
		"events": events,
		"segments": twitch,
		"paired_events": paired_events,
	]);
	send_updates_all("#" + userid);
}

__async__ mapping|zero wscmd_fetchcal(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->calendarid)) return 0;
	string calendarid = msg->calendarid;
	//TODO: Allow hash character in calendar ID, and properly encode. Probably not common but we should allow all valid calendar IDs.
	//Be sure to also properly encode any use of cfg->gcal_sync in a URL too.
	sscanf(calendarid, "%*[A-Za-z0-9@.]%s", string residue); if (residue != "") return 0;
	mapping events = await(google_api("calendar/v3/calendars/" + calendarid + "/events", "apikey", ([
		"variables": ([
			"singleEvents": "true", "orderBy": "startTime",
			"timeMin": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time())),
			"timeMax": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time() + 604800)), //Give us one week's worth of events for a quick preview
		])]),
	));
	if (events->error) {
		if (events->error->code == 404) {
			//Either you hacked around in the page, or you tried to query a private calendar.
			//Assume the latter and report it accordingly.
			return (["cmd": "privatecalendar", "calendarid": msg->calendarid]);
		}
		werror("ERROR FETCHING CALENDAR %O %O %O\n", channel, msg, events);
		return 0;
	}
	return (["cmd": "showcalendar", "calendarid": msg->calendarid, "events": events]);
}

__async__ mapping|zero wscmd_synchronize(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->calendarid)) return 0;
	sscanf(msg->calendarid, "%*[A-Za-z0-9@.]%s", string residue); if (residue != "") return 0;
	string|zero token = await(G->G->DB->load_config(channel->userid, "calendar"))->oauth->?access_token;
	if (!token) return 0;
	string now = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time()));
	mapping details = await(google_api("calendar/v3/calendars/" + msg->calendarid + "/events", token, ([
		"variables": (["timeMin": now, "timeMax": now]), //Don't actually need any events, just metadata
	])));
	mapping resp = await(google_api("calendar/v3/calendars/" + msg->calendarid + "/events/watch", token, ([
		"json": ([
			"id": MIME.encode_base64(random_string(9)),
			"type": "webhook",
			"address": G->G->instance_config->http_address + "/channels/" + channel->login + "/calendar",
		]),
	])));
	await(G->G->DB->mutate_config(channel->userid, "calendar") {mapping cfg = __ARGS__[0];
		cfg->gcal_sync = msg->calendarid;
		cfg->gcal_resource_id = resp->resourceId;
		cfg->gcal_calendar_name = details->summary;
		cfg->gcal_time_zone = details->timeZone;
	});
	synchronize(channel->userid);
}

//Shouldn't normally be necessary (the webhook will trigger resyncs as needed), but people can push a
//"make me feel comfortable" button. Also good for testing.
void wscmd_force_resync(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	fetch_calendar_info(channel->userid); //Skipped if we don't have the right auth
	synchronize(channel->userid);
}

@retain: mapping google_logins_pending = ([]);
__async__ mapping wscmd_googlelogin(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string state = MIME.encode_base64(random_string(15));
	string redirect_uri = "https://" + G->G->instance_config->local_address + "/junket";
	google_logins_pending[state] = (["time": time(), "channel": channel->userid, "redirect_uri": redirect_uri]);
	mapping cred = await(G->G->DB->load_config(0, "googlecredentials"));
	string uri = "https://accounts.google.com/o/oauth2/auth?" + Protocols.HTTP.http_encode_query(([
		"scope": ({
			"https://www.googleapis.com/auth/calendar.calendarlist.readonly",
			"https://www.googleapis.com/auth/calendar.events.public.readonly",
			//Need this scope to query the user's profile or see the id token
			"https://www.googleapis.com/auth/userinfo.profile",
		}) * " ",
		"client_id": cred->client_id,
		"redirect_uri": redirect_uri,
		"response_type": "code", "access_type": "offline", "include_granted_scopes": "true",
		"state": state,
	]));
	return (["cmd": "googlelogin", "uri": uri]);
}

protected void create(string name) {::create(name); /*synchronize(49497888);*/}
