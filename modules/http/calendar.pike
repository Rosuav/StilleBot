inherit http_endpoint;

constant form = #"
<form method=get>
<label>Select channel: <input name=for></label>
<input type=submit value=Go>
</form>
";

constant markdown = #"# Twitch stream calendar for $$chan$$

$$events$$

Add this streamer's schedule to some other calendar service (eg Google Calendar) using
this URL: [$$calurl$$]($$calurl$$)

" + form;

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string chan = req->variables["for"];
	if (!chan) return render_template("# Twitch stream calendar\n\n" + form, ([]));
	int id = yield(get_user_id(chan));
	//NOTE: Do not use get_helix_paginated here as the events probably go on forever.
	array events = ({ });
	string cursor = "";
	object nw = Calendar.ISO.Second()->add(86400 * 7);
	string next_week = nw->format_ymd() + "T" + nw->format_tod() + "Z";
	while (1) {
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id + "&after=" + cursor + "&first=25"));
		chan = info->data->broadcaster_name || chan;
		cursor = info->pagination->?cursor;
		foreach (info->data->segments, mapping ev) {
			if (ev->start_time > next_week) {cursor = 0; break;}
			string datedesc = ev->start_time; //TODO: Format this nicely
			events += ({sprintf("* <time datetime=\"%s\">%s</time> %s", ev->start_time, datedesc, ev->title)});
		}
		if (!cursor) break;
	}
	return render_template(markdown, ([
		"chan": chan,
		"events": sizeof(events) ? events * "\n" : "* No scheduled streams",
		"calurl": "https://api.twitch.tv/helix/schedule/icalendar?broadcaster_id=" + id,
	]));
}
