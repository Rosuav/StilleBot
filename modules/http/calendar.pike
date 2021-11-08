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
	mapping info = yield(get_user_info(chan, "login"));
	array events = yield(get_stream_schedule(info->id, 0, 100, 86400 * 7));
	events = map(events) {[mapping ev] = __ARGS__;
		string datedesc = ev->start_time; //TODO: Format this nicely
		return sprintf("* <time datetime=\"%s\">%s</time> %s", ev->start_time, datedesc, ev->title);
	};
	return render_template(markdown, ([
		"chan": info->display_name,
		"events": sizeof(events) ? events * "\n" : "* No scheduled streams",
		"calurl": "https://api.twitch.tv/helix/schedule/icalendar?broadcaster_id=" + info->id,
	]));
}
