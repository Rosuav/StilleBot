inherit http_websocket;
inherit builtin_command;
inherit annotated;
/* On-screen labels

TODO: Make a separate element for removing a label. Internally it's the same builtin with parameters
{labelid} and duration -1.

TODO: Max labels (if one is created when at max, discard the oldest)
- Newest at bottom vs newest at top
*/
constant STYLES = #"
#activelabels {
	padding: 0;
}
#activelabels li {
	width: max-content;
	list-style-type: none;
}";
constant markdown = #"# On-screen labels

Show information in OBS when things happen.

> <summary>Preview</summary>
> <div id=display></div>
{:tag=details}

Drag this to OBS, or use this URL as a browser source: [On Screen Labels](labels?key=$$accesskey$$ :#displaylink)

Keep this link secret; if the authentication key is accidentally shared, you can [Revoke Key](:#revokeauth) to generate a new one.

> [Save](:type=submit)
{:tag=form}

<style>
details {
	border: 1px solid black;
	margin-bottom: 0.5em;
}" + STYLES + #"
</style>
";

@retain: mapping channel_labels = ([]);

constant builtin_name = "Labels"; //The front end may redescribe this according to the parameters
constant builtin_description = "Create or remove an on-screen label";
constant builtin_param = ({"Text", "Duration", "/Countdown/=No countdown/ss=Seconds (eg 59)/mmss=Min:Sec (eg 05:00)/mm=Minutes (eg 05)"});
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{labelid}": "ID of the newly-created label - can be used to remove it later",
]);

//Attempt to remove a label by its ID. Returns the ID if found.
string remove_label(string chan, string labelid) {
	mapping labels = G_G_("channel_labels", chan);
	foreach (labels->active || ({ }); int i; mapping lbl) if (lbl->id == labelid) {
		labels->active = labels->active[..i-1] + labels->active[i+1..];
		update_one("#" + chan, labelid);
		return labelid;
	}
}

mapping|Concurrent.Future message_params(object channel, mapping person, array param) {
	if (param[0] == "") return (["{error}": "Need a label to work with"]);
	string chan = channel->name[1..];
	mapping labels = G_G_("channel_labels", chan);
	string labelid;
	int duration = (int)param[1];
	if (duration == -1) {
		//Delete an existing label
		labelid = remove_label(chan, param[0]);
		if (!labelid) return (["{error}": "Label ID not found for deletion: " + param[0]]);
	} else {
		//Create a new label
		labels->active += ({([
			"id": labelid = "lbl-" + labels->nextid++,
			"bread": duration > 0 && time() + duration,
			"label": param[0],
			"timefmt": (<"mm", "mmss", "ss">)[param[2]] ? param[2] : "",
		])});
		if (duration > 0) call_out(remove_label, duration, chan, labelid);
		update_one("#" + chan, labelid);
	}
	return ([
		"{labelid}": labelid,
		"{error}": "",
	]);
}

string get_access_key(string chan) {
	mapping cfg = persist_status->path("channel_labels", chan);
	if (!cfg->accesskey) {cfg->accesskey = String.string2hex(random_string(13)); persist_status->save();}
	return cfg->accesskey;
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	//TODO: If fake, show something?? maybe?? Borrow ideas from alertbox demo mode.
	//TODO: If ?key=x passed, but key is incorrect, give an immediate failure (don't wait for WS failure)
	if (req->variables->key) return render_template("monitor.html", ([
		"vars": (["ws_type": ws_type, "ws_group": req->variables->key + req->misc->channel->name, "ws_code": "chan_labels"]),
		"title": "Channel labels", "styles": STYLES,
	]));
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	return render(req, ([
		"vars": (["ws_group": ""]),
		"accesskey": get_access_key(req->misc->channel->name[1..]),
	]) | req->misc->chaninfo);
}

//HACK: A non-blank group is the access key. If it is correct, override the group to
//blank and bypass the moderator check. Otherwise, nonblank groups are rejected and
//other checks are passed up the line (which will include rejecting non-mods).
bool need_mod(string grp) {return 1;}
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->group)) return "Bad group";
	sscanf(msg->group, "%s#%s", string subgroup, string chan);
	if (subgroup == "") return ::websocket_validate(conn, msg);
	string key = persist_status->has_path("channel_labels", chan)->?accesskey;
	if (subgroup != key) return "Bad key";
	msg->group = "#" + chan; //effectively, subgroup becomes blank
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping labels = G_G_("channel_labels", channel->name[1..]);
	mapping cfg = persist_status->path("channel_labels", channel->name[1..]);
	if (id) {
		foreach (labels->active || ({}), mapping lbl)
			if (lbl->id == id) return lbl;
		return 0;
	}
	return ([
		"items": labels->active || ({}),
		"style": cfg->style || ([]),
		"css": textformatting_css(cfg->style || ([])),
	]);
}

@"is_mod": void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = persist_status->path("channel_labels", channel->name[1..]);
	//Assume that any update completely rewrites the formatting
	mapping style = ([]);
	foreach (TEXTFORMATTING_ATTRS, string attr) style[attr] = msg[attr];
	textformatting_validate(style);
	cfg->style = style;
	//Save anything else eg max labels to show
	persist_status->save();
	send_updates_all(channel->name);
}

@"is_mod": void wscmd_revokekey(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("channel_labels", channel->name[1..]);
	m_delete(cfg, "accesskey");
	string newkey = get_access_key(channel->name[1..]);
	//Non-mod connections get kicked
	foreach (websocket_groups[channel->name], object sock)
		if (!sock->query_id()->is_mod) sock->close();
	//Other mod connections remain but will have the wrong key. Only THIS connection gets the new one.
	conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": newkey]), 4));
}

protected void create(string name) {::create(name);}
