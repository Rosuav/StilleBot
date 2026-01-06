//NOTE: This currently two-letter collides with /c/pointsrewards; see there for
//plans to resolve this. Normally the last one created has to rename, which is
//how we got the clunky "pointsrewards" in the first place (due to /c/repeats),
//but this really needs the name /c/polls and I don't think there's a better name.
inherit http_websocket;

//TODO: Copy in the !!pollbegin and !!pollended specials so they can be edited here too

constant markdown = #"# Polls

When you run a poll on your channel, it will show up here. You can rerun any poll
or make adjustments, and go back and see the past polls and their results.

Created | Last asked | Title | Options | Duration | Results |
--------|------------|-------|---------|----------|---------|-
loading... | -
{:#polls}

<form id=config>
<table>
<tr><td>Date:</td><td><input name=created readonly> <input name=lastused readonly></td></tr>
<tr><td><label for=title>Title:</label></td><td><input id=title name=title size=80></td></tr>
<tr><td><label for=options>Options:</label></td><td><textarea id=options name=options rows=5 cols=80 placeholder='Yes&#10;No'></textarea></td></tr>
<tr><td><label for=duration>Duration:</label></td><td><select id=duration name=duration><option value=60>One minute</select></td></tr>
<tr><td>Results:</td><td>TODO</td></tr>
</table>
<button type=submit>Ask this!</button>
</form>

<style>
#polls tbody tr:nth-child(odd) {
	background: #ddf;
	cursor: pointer;
}

#polls tbody tr:nth-child(even) {
	background: #dff;
	cursor: pointer;
}

#polls tbody tr:hover {
	background: #ff0;
}

input[readonly] {
	background-color: #ddd;
}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	//TODO: Should non-mods be allowed to see past polls?
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	if (string scopes = req->misc->channel->userid && ensure_bcaster_token(req, "channel:manage:polls"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;} //TODO as above: Should non-mods be allowed to see past polls?
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(G->G->DB->load_config(channel->userid, "polls"));
	return ([
		"polls": info->polls || ({ }),
	]);
}

//TODO: Trigger this when Twitch says a poll happened
void addpoll(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "polls") {mapping info = __ARGS__[0];
		//TODO: Search for an existing poll with the same title and options
		msg->created = msg->lastused = time();
		info->polls += ({msg & (<"created", "lastused", "title", "options">)});
	}->then() {send_updates_all(channel, "");};
}

void wscmd_delpoll(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "polls") {mapping info = __ARGS__[0];
		if (!intp(msg->idx) || msg->idx < 0 || msg->idx >= sizeof(info->polls)) return;
		info->polls[msg->idx] = 0; info->polls -= ({0});
	}->then() {send_updates_all(channel, "");};
}

void wscmd_askpoll(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string title = String.trim(msg->title || "");
	if (title == "") return;
	array options = String.trim((msg->options / "\n")[*]) - ({""});
	switch (sizeof(options)) {
		case 0: options += ({"Yes"}); //fall through
		case 1:
			//Hack. Maybe it'd be better to return an error?
			if (options[0] == "No") options += ({"Yes"});
			else options += ({"No"});
			break;
		case 2: case 3: case 4: case 5: break;
		default: options = options[..4]; //TODO: Give an error instead?
	}
	int duration = (int)msg->duration || 300;
	twitch_api_request("https://api.twitch.tv/helix/polls",
		(["Authorization": channel->userid]),
		(["method": "POST", "return_errors": 1, "json": ([
			"broadcaster_id": channel->userid,
			"title": title,
			"choices": (["title": options[*]]),
			"duration": duration,
		])]));
}

//protected void create(string name) {::create(name);}
