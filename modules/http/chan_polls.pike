//NOTE: This currently two-letter collides with /c/pointsrewards; see there for
//plans to resolve this. Normally the last one created has to rename, which is
//how we got the clunky "pointsrewards" in the first place (due to /c/repeats),
//but this really needs the name /c/polls and I don't think there's a better name.
inherit http_websocket;
inherit hook;

//TODO: Copy in the !!pollbegin and !!pollended specials so they can be edited here too

constant markdown = #"# Polls

When you run a poll on your channel, it will show up here. You can rerun any poll
or make adjustments, and go back and see the past polls and their results.

Created | Last asked | Title | Options | Duration | Pts/vote | Latest Results |
--------|------------|-------|---------|----------|----------|----------------|-
loading... | -
{:#polls}

<form id=config>
<table>
<tr><td>Date:</td><td><input name=created readonly> <input name=lastused readonly></td></tr>
<tr><td><label for=title>Title:</label></td><td><input id=title name=title size=80></td></tr>
<tr><td><label for=options>Options:</label></td><td><textarea id=options name=options rows=5 cols=80 placeholder='Yes&#10;No'></textarea></td></tr>
<tr><td><label for=duration>Duration:</label></td><td><select id=duration name=duration><option value=15>15 secs<option value=60>One minute<option value=300>Five minutes</select></td></tr>
<tr><td><label for=points>Extra votes:</label></td><td><input id=points name=points type=number value=0> channel points to buy an extra vote, 0 to disable</td></tr>
<tr><td>Results:</td><td id=resultsummary></td></tr>
<tr><td></td><td id=resultdetails></td></tr>
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

@EventNotify("channel.poll.begin=1", ({"channel:read:polls", "channel:manage:polls"})):
void addpoll(object channel, mapping data) {
	G->G->DB->mutate_config(channel->userid, "polls") {mapping info = __ARGS__[0];
		if (!info->polls) info->polls = ({ });
		string options = data->choices->title * "\n";
		int idx = -1;
		foreach (info->polls; int i; mapping p)
			if (p->title == data->title && p->options == options) {idx = i; break;}
		if (idx == -1) info->polls += ({([
			"title": data->title,
			"options": options,
			"created": time(),
			"results": ({ }),
		])});
		//Note that, if one wasn't found, idx will still be -1 and so we'll update the last entry in the array
		info->polls[idx]->lastused = time();
		info->polls[idx]->points = data->channel_points_voting->is_enabled ? data->channel_points_voting->amount_per_vote : 0;
		info->polls[idx]->duration = time_from_iso(data->ends_at)->unix_time() - time_from_iso(data->started_at)->unix_time();
	}->then() {send_updates_all(channel, "");};
}

@EventNotify("channel.poll.end=1", ({"channel:read:polls", "channel:manage:polls"})):
void pollresult(object channel, mapping data) {
	G->G->DB->mutate_config(channel->userid, "polls") {mapping info = __ARGS__[0];
		if (!info->polls) return; //Obviously no match
		string options = data->choices->title * "\n";
		int idx = -1;
		foreach (info->polls; int i; mapping p)
			if (p->title == data->title && p->options == options) {idx = i; break;}
		if (idx == -1) return; //No match? Possibly means we didn't see the begin-poll message.
		if (has_value(info->polls[idx]->results->id, data->id)) return; //We already have the results for this poll; it's probably just gotten archived.
		//The choices array contains some junk, like bits_votes (always zero - once upon
		//a time, you could pay bits to vote), so we filter them. If Twitch adds more info,
		//we want to keep that, so just delete the ones we know aren't of interest.
		foreach (data->choices, mapping c) {m_delete(c, "bits_votes"); m_delete(c, "id");}
		info->polls[idx]->results += ({([
			"id": data->id,
			"completed": time(),
			"options": data->choices,
		])});
	}->then() {send_updates_all(channel, "");};
}

void wscmd_delpoll(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "polls") {mapping info = __ARGS__[0];
		if (!intp(msg->idx) || msg->idx < 0 || msg->idx >= sizeof(info->polls)) return;
		info->polls[msg->idx] = 0; info->polls -= ({0});
	}->then() {send_updates_all(channel, "");};
}

__async__ void wscmd_askpoll(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
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
	mapping ret = await(twitch_api_request("https://api.twitch.tv/helix/polls",
		(["Authorization": channel->userid]),
		(["method": "POST", "return_errors": 1, "json": ([
			"broadcaster_id": channel->userid,
			"title": title,
			"choices": (["title": options[*]]),
			"duration": duration,
			"channel_points_voting_enabled": (int)msg->points ? Val.true : Val.false,
			"channel_points_per_vote": (int)msg->points,
		])])));
	if (ret->error) {
		werror("FAILED TO START POLL %O\n", ret);
		//TODO: Push this out to the front end
	}
}

protected void create(string name) {::create(name);}
