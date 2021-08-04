inherit http_endpoint;

constant form = #"
<form method=get>
<label>Select channel: <input name=for></label>
<input type=submit value=Go>
</form>
";

constant markdown = #"# Twitch stream calendar for channel $$chan$$

* Events will go here

Add this streamer's schedule to some other calendar service (eg Google Calendar) using
this URL: [$$calurl$$]($$calurl$$)

" + form;

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string chan = req->variables["for"];
	if (!chan) return render_template("# Twitch stream calendar\n\n" + form, ([]));
	int id = yield(get_user_id(chan));
	return render_template(markdown, ([
		"chan": chan,
		"calurl": "https://api.twitch.tv/helix/schedule/icalendar?broadcaster_id=" + id,
	]));
}
