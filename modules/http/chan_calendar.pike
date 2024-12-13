inherit annotated;
inherit http_websocket;

constant markdown = #"# Synchronize Google and Twitch calendars

Enter the calendar ID directly, or [log in with Google](:#googleoauth) to select from your calendars (not yet available).

<input name=calendarid size=80> [Preview](:#calsync)

<section id=calendar></section>
";

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"content-type">);
		werror("Forwarding calendar webhook...\n");
		Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
			Protocols.HTTP.Promise.Arguments((["headers": req->request_headers & headers, "data": req->body_raw])));
		//As elsewhere, not currently awaiting the promise. Should we?
		return "Passing it along.";
	}
	//TODO: Handle webhooks, notably sending updates all any time the calendar changes
	if (string calid = req->request_type == "POST" && req->request_headers["x-goog-resource-id"]) {
		werror("CALENDAR WEBHOOK\nHeaders %O\nBody: %O\n", req->request_headers, req->body_raw);
		//Note that the webhook doesn't actually say what changed, just that a change happened.
		//So the easiest thing here will be to trigger a full resync as soon as any change occurs.
		return "Okay.";
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp) {
	//TODO: Show the current calendar
	return ([]);
}

__async__ mapping|zero wscmd_fetchcal(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->calendarid)) return 0;
	sscanf(msg->calendarid, "%*[A-Za-z0-9@.]%s", string residue); if (residue != "") return 0;
	string apikey = await(G->G->DB->load_config(0, "googlecredentials"))->calendar;
	object res = await(Protocols.HTTP.Promise.get_url("https://www.googleapis.com/calendar/v3/calendars/" + msg->calendarid + "/events",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"X-goog-api-key": apikey,
		])]))
	));
	mapping events = Standards.JSON.decode_utf8(res->get());
	return (["cmd": "showcalendar", "calendarid": msg->calendarid, "events": events]);
}

__async__ mapping|zero wscmd_synchronize(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->calendarid)) return 0;
	sscanf(msg->calendarid, "%*[A-Za-z0-9@.]%s", string residue); if (residue != "") return 0;
	string|zero token = await(G->G->DB->load_config(channel->userid, "calendar"))->oauth->?access_token;
	if (!token) return 0;
	string apikey = await(G->G->DB->load_config(0, "googlecredentials"))->calendar;
	object res = await(Protocols.HTTP.Promise.post_url("https://www.googleapis.com/calendar/v3/calendars/" + msg->calendarid + "/events/watch",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + token,
			"Content-Type": "application/json; charset=utf-8",
		]), "data": Standards.JSON.encode(([
			"id": MIME.encode_base64(random_string(9)),
			"type": "webhook",
			"address": G->G->instance_config->http_address + "/channels/" + channel->login + "/calendar",
		]), 1)]))
	));
	mapping resp = Standards.JSON.decode_utf8(res->get());
	werror("RESPONSE: %O\n", resp);
	await(G->G->DB->mutate_config(channel->userid, "calendar") {mapping cfg = __ARGS__[0];
		cfg->gcal_sync = msg->calendarid;
		cfg->gcal_resource_id = resp->resourceId;
	});
	send_updates_all(channel, "");
}

@retain: mapping google_logins_pending = ([]);
__async__ mapping wscmd_googlelogin(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string state = MIME.encode_base64(random_string(15));
	string redirect_uri = "https://" + G->G->instance_config->local_address + "/junket";
	google_logins_pending[state] = (["time": time(), "channel": channel->userid, "redirect_uri": redirect_uri]);
	mapping cred = await(G->G->DB->load_config(0, "googlecredentials"));
	string uri = "https://accounts.google.com/o/oauth2/auth? " + Protocols.HTTP.http_encode_query(([
		"scope": "https://www.googleapis.com/auth/calendar.readonly",
		"client_id": cred->client_id,
		"redirect_uri": redirect_uri,
		"response_type": "code", "access_type": "offline", "include_granted_scopes": "true",
		"state": state,
	]));
	return (["cmd": "googlelogin", "uri": uri]);
}

protected void create(string name) {::create(name);}
