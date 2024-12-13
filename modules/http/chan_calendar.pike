inherit annotated;
inherit http_websocket;

constant markdown = #"# Synchronize Google and Twitch calendars

Enter the calendar ID directly, or [log in with Google](:#googleoauth) to select from your calendars (not yet available).

<input name=calendarid size=80> [Synchronize](:#calsync)

<section id=calendar></section>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	//TODO: Handle webhooks, notably sending updates all any time the calendar changes
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
	return (["cmd": "showcalendar", "events": events]);
}

protected void create(string name) {::create(name);}
