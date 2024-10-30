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

Format for Discord: <select id=fmt><option value=''>Default<option value=t>Short time<option value=T>Long time<option value=f>Short date/time<option value=F>Long date/time<option value=R>Relative</select> <code id=output></code>

<script type=module>
import {choc, set_content, DOM, on} from \"https://rosuav.github.io/choc/factory.js\";
let fmt = '', ts = 0;
function update() {
	if (!ts) set_content('#output', 'Pick a calendar event');
	else if (fmt === '') set_content('#output', '<t:' + ts + '>');
	else set_content('#output', '<t:' + ts + ':' + fmt + '>');
}
on('change', '#fmt', e => {fmt = e.match.value; update();});
on('click', 'input[type=radio]', e => {ts = e.match.value; update();});
</script>

" + form;

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string chan = req->variables["for"];
	if (!chan) return render_template("# Twitch stream calendar\n\n" + form, ([]));
	mapping info = await(get_user_info(chan, "login"));
	array events = await(get_stream_schedule(info->id, 0, 100, 86400 * 7));
	events = map(events) {[mapping ev] = __ARGS__;
		string datedesc = ev->start_time; //TODO: Format this nicely
		object t = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", ev->start_time);
		return sprintf("* <label><input type=radio name=ts value=%d><time datetime=\"%s\">%s</time> %s</label>",
			t->unix_time(), ev->start_time, datedesc, ev->title);
	};
	return render_template(markdown, ([
		"chan": info->display_name,
		"events": sizeof(events) ? events * "\n" : "* No scheduled streams",
		"calurl": "https://api.twitch.tv/helix/schedule/icalendar?broadcaster_id=" + info->id,
	]));
}
