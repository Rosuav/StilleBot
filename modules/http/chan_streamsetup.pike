inherit builtin_command;
inherit http_websocket;

//TODO: Document the fact that tags and CCLs can be added to with "+tagname" and removed
//from with "-tagname". It's a useful feature but hard to explain compactly.

/* TODO: Migrate in functionality from mustard-mine.herokuapp.com

* User checklist
* Setups. Store an array in a single DB config entry. No need for anything to do with tweets, but have a Comments field.
* Import from old Mustard Mine
  - Save the setups and checklist into save_config("streamsetups")
  - Automatically create timers for chan_monitors
*/

constant markdown = #"# Stream setup

TODO. Massive massive TODO.

On this page you can to configure your broadcast's category, title, tags, and content classification labels.

Saved setups allow you to quickly select commonly-used settings. They have unique IDs that can be used to apply them from commands.

You can create [commands](commands) that change these same settings.

Were you using the old Mustard Mine? [Import your settings here!](: .opendlg data-dlg=importdlg)

Category | Title | Tags | CCLs | Comments |
---------|-------|------|------|----------|-
loading... | - | - | - | - | -
{:#setups}

<div id=prevsetup></div>
<form id=setupconfig>
<table>
<tr>
	<td><label for=category>Category:</label></td>
	<td><input id=category name=category size=30><button id=pick_cat type=button>Pick</button></td>
</tr>
<tr><td><label for=ccls>Classification:</label></td><td><input id=ccls name=ccls size=118 readonly> <button id=pick_ccls type=button>Pick</button></td></tr>
<tr><td><label for=title>Stream title:</label></td><td><input id=title name=title size=125></td></tr>
<tr><td>Tags:</td><td><input id=tags name=tags size=125></td></tr>
<tr><td colspan=2>Separate multiple tags with commas.</td></tr>
<tr><td><label for=comments>Comments:</td><td><textarea id=comments name=comments></textarea></td></tr>
</table>
<button type=submit>Update stream info</button> <button type=button id=save>Save this setup</button>
</form>

> ### Import old settings
>
> Were you previously using [the old Mustard Mine](https://mustard-mine.herokuapp.com/)? You can
> export settings from there (scroll all the way down) and import them here.
>
> <input type=file accept=application/json>
>
> [Close](:.dialog_close)
{: tag=dialog #importdlg}

<style>
#setups tbody tr:nth-child(odd) {
	background: #ddf;
	cursor: pointer;
}

#setups tbody tr:nth-child(even) {
	background: #dff;
	cursor: pointer;
}

#setups tbody tr:hover {
	background: #ff0;
}

#prevsetup {
	margin: 0.25em;
	padding: 0.25em;
	border: 1px solid blue;
	display: none;
}
#prevsetup span {
	margin: 0 0.5em;
}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	if (string scopes = req->misc->channel->userid && ensure_bcaster_token(req, "channel:manage:broadcast"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	array prev;
	if (req->misc->channel->userid) prev = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + req->misc->channel->userid))->data;
	else prev = ({([ //Sample data for the demo channel
		"game_name": "Software and Game Development",
		"tags": "TwitchChannelBot Demo HelloWorld" / " ",
		"content_classification_labels": ({ }),
		"title": "Example title of an example stream",
	])});
	return render(req, ([
		"vars": (["ws_group": "", "initialsetup": sizeof(prev) && prev[0]]),
	]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(G->G->DB->load_config(channel->userid, "streamsetups"));
	return ([
		"checklist": info->checklist || "",
		"items": info->setups || ({ }),
	]);
}

@"is_mod": void wscmd_newsetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "streamsetups") {
		if (!stringp(msg->id)) msg->id = MIME.encode_base64(random_string(9)); //Allow the user to specify an ID, otherwise autogenerate
		__ARGS__[0]->setups = filter(__ARGS__[0]->setups) {return __ARGS__[0]->id != msg->id;}
			+ ({msg & (<"id", "category", "title", "tags", "ccls", "comments">)});
	}->then() {send_updates_all(channel, "");};
}

@"is_mod": void wscmd_delsetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "streamsetups") {
		if (msg->id == "undefined") msg->id = 0;
		__ARGS__[0]->setups = filter(__ARGS__[0]->setups) {return __ARGS__[0]->id != msg->id;};
	}->then() {send_updates_all(channel, "");};
}

@"is_mod": __async__ void wscmd_applysetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Note that this does NOT apply by ID; it sets all the specifics.
	mapping params = ([]);
	if (msg->title) params->title = msg->title; //Easy.
	if (msg->tags) params->tags = String.trim((msg->tags / ",")[*]);
	//TODO: CCLs, category
	mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid));
	prev = prev->data[0];
	prev->tags *= ", ";
	//TODO: Reformat CCLs too
	await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": params, "return_errors": 1]),
	));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "prevsetup", "setup": prev])));
}

constant builtin_name = "Stream setup";
constant builtin_param = ({"/Action/query/title/category/tags/ccls", "New value"});
constant scope_required = "channel:manage:broadcast"; //If you only use "query", it could be done without privilege, though.
constant vars_provided = ([
	"{prevtitle}": "Stream title prior to any update",
	"{newtitle}": "Stream title after any update",
	"{prevcat}": "Stream category prior to any update",
	"{newcat}": "Stream category after any update",
	"{prevtags}": "All tags (space-separated) prior to any update",
	"{newtags}": "All tags after any update",
	"{prevccls}": "Active CCLs prior to any update",
	"{newccls}": "Active CCLs after any update",
]);

__async__ mapping message_params(object channel, mapping person, array param) {
	string token = token_for_user_id(channel->userid)[0];
	if (token == "") error("Need broadcaster permissions\n");
	mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token])));
	mapping params = ([]);
	int empty_ok = 0;
	foreach (param / 2, [string cmd, string arg]) {
		switch (cmd) {
			case "title": params->title = arg; break;
			case "category": error("UNIMPLEMENTED - need to look up game ID\n"); break;
			case "tags": {
				//On Twitch's side, you always replace all tags. So we take the previous and modify.
				if (!params->tags) params->tags = prev->tags;
				if (arg != "" && arg[0] == '+') params->tags += ({arg[1..]});
				else if (arg != "" && arg[0] == '-') params->tags -= ({arg[1..]});
				else params->tags = arg / " ";
				break;
			}
			case "ccls": {
				//This is the opposite: you make the changes you want to make. So if the user asks
				//to set all of them, we need to explicitly state them all.
				if (!params->content_classification_labels) params->content_classification_labels = ({ });
				if (arg != "" && arg[0] == '+') params->content_classification_labels += ({(["id": arg[1..], "is_enabled": 1])});
				else if (arg != "" && arg[0] == '-') params->content_classification_labels += ({(["id": arg[1..], "is_enabled": 0])});
				else {
					multiset is_enabled = (multiset)(arg / " ");
					if (!G->G->ccl_names) {
						//NOTE: Partly duplicated from raid finder. Should this be deduped?
						array ccls = await(twitch_api_request("https://api.twitch.tv/helix/content_classification_labels"))->data;
						G->G->ccl_names = mkmapping(ccls->id, ccls->name);
					}
					params->content_classification_labels = mkmapping(indices(G->G->ccl_names), is_enabled[indices(G->G->ccl_names)[*]]);
				}
				break;
			}
			case "query": empty_ok = 1; break; //Query-only. Other modes will also query, but you can use this to avoid making unwanted changes.
			default: error("Unknown action %O\n", cmd);
		}
	}
	mapping now;
	if (sizeof(params)) {
		mapping ret = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": params, "return_errors": 1]),
		));
		if (ret->error) error(ret->error + ": " + ret->message + "\n");
		now = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
			(["Authorization": "Bearer " + token])));
	} else {
		if (!empty_ok) error("No changes requested\n");
		now = prev;
	}
	mapping resp = ([]);
	foreach ((["prev": prev, "new": now]); string lbl; mapping ret) {
		if (!arrayp(ret->data) || !sizeof(ret->data)) continue; //No useful data available. Shouldn't normally happen.
		resp["{" + lbl + "title}"] = ret->data[0]->title || "";
		resp["{" + lbl + "cat}"] = ret->data[0]->game_name || "";
		resp["{" + lbl + "tags}"] = ret->data[0]->tags * " ";
		resp["{" + lbl + "ccls}"] = ret->data[0]->content_classification_labels * " ";
	}
	return resp;
}

protected void create(string name) {::create(name);}
