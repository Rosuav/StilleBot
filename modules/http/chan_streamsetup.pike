inherit builtin_command;
inherit http_websocket;

//TODO: Document the fact that tags and CCLs can be added to with "+tagname" and removed
//from with "-tagname". It's a useful feature but hard to explain compactly.

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
<tr><td colspan=2>Separate multiple tags/CCLs with commas.</td></tr>
<tr><td><label for=comments>Comments:</td><td><textarea id=comments name=comments rows=5 cols=80></textarea></td></tr>
</table>
<button type=submit>Update stream info</button> <button type=button id=save>Save this setup</button>
</form>

> ### Import old settings
>
> Were you previously using [the old Mustard Mine](https://mustard-mine.herokuapp.com/)? You can
> export settings from there (scroll all the way down) and import them here.
>
> <input id=importfile type=file accept=application/json>
>
> [Import](:#importsettings disabled=true) [Close](:.dialog_close)
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

> ### Pick a category
>
> <input id=picker_search size=50>
> <ul id=picker_results></ul>
>
> [Cancel](:.dialog_close)
{: tag=dialog #categorydlg}

<!-- -->

> ### Select CCLs
>
> Select the classification labels appropriate to your stream. Be sure to follow
> [Twitch's rules about CCLs](https://help.twitch.tv/s/article/content-classification-labels)
> and [applicable guidelines](https://safety.twitch.tv/s/article/Content-Classification-Guidelines)
>
> $$ccl_options$$
> {:#ccl_options}
>
> [Apply](:#ccl_apply) [Cancel](:.dialog_close)
{: tag=dialog #cclsdlg}
";

//Cached. Should we go recheck it at any point?
@retain: array ccl_options;

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
		"ccl_options": map(ccl_options) { mapping ccl = __ARGS__[0];
			return sprintf("* <label><input type=checkbox name=%s> %s<br><i>%s</i>", ccl->id, ccl->name, ccl->description);
		} * "\n",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(G->G->DB->load_config(channel->userid, "streamsetups"));
	return ([
		"checklist": info->checklist || "", //TODO: Not implemented on front end yet
		"items": info->setups || ({ }),
	]);
}

void wscmd_newsetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "streamsetups") {
		if (!stringp(msg->id)) msg->id = MIME.encode_base64(random_string(9)); //Allow the user to specify an ID, otherwise autogenerate
		__ARGS__[0]->setups = filter(__ARGS__[0]->setups) {return __ARGS__[0]->id != msg->id;}
			+ ({msg & (<"id", "category", "title", "tags", "ccls", "comments">)});
	}->then() {send_updates_all(channel, "");};
}

void wscmd_delsetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "streamsetups") {
		__ARGS__[0]->setups = filter(__ARGS__[0]->setups) {return __ARGS__[0]->id != msg->id;};
	}->then() {send_updates_all(channel, "");};
}

__async__ void wscmd_applysetup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Note that this does NOT apply by ID; it sets all the specifics.
	mapping params = ([]);
	if (msg->title && msg->title != "") params->title = msg->title; //Easy.
	if (msg->tags) params->tags = String.trim((msg->tags / ",")[*]) - ({""});
	if (msg->ccls) {
		//Twitch expects us to show "add/remove" for each CCL. So if you select a specific
		//set of them, we apply a change to every known CCL.
		multiset is_enabled = (multiset)String.trim((msg->ccls / ",")[*]);
		params->content_classification_labels = map(ccl_options->id) {return (["id": __ARGS__[0], "is_enabled": is_enabled[__ARGS__[0]]]);};
	}
	mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid));
	prev = prev->data[0];
	prev->tags *= ", ";
	prev->ccls = prev->content_classification_labels * ", ";
	mapping ret = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": params, "return_errors": 1]),
	));
	//TODO: Report errors
	conn->sock->send_text(Standards.JSON.encode((["cmd": "prevsetup", "setup": prev])));
}

__async__ void wscmd_catsearch(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array ret = ({ });
	if (msg->q != "") ret = await(twitch_api_request("https://api.twitch.tv/helix/search/categories?first=5&query="
			+ Protocols.HTTP.uri_encode(msg->q))
		)->data;
	send_msg(conn, (["cmd": "catsearch", "results": ret]));
}

void wscmd_import(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "streamsetups") { mapping cfg = __ARGS__[0];
		foreach (msg->data->setups || ({ }), mapping|string setup) if (mappingp(setup)) {
			setup->id = MIME.encode_base64(random_string(9));
			setup->comments = m_delete(setup, "tweet") || ""; //Tweets aren't supported, but comments are new (and mean we don't lose any data)
			cfg->setups += ({setup});
		}
		if (arrayp(msg->data->checklist)) cfg->checklist = String.trim(msg->data->checklist * "\n");
	}->then() {send_updates_all(channel, "");};
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
					params->content_classification_labels = map(indices(G->G->ccl_names)) {return (["id": __ARGS__[0], "is_enabled": is_enabled[__ARGS__[0]]]);};
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

protected void create(string name) {
	if (!G->G->ccl_names || !ccl_options) {
		//NOTE: Partly duplicated from raid finder. Should this be deduped?
		twitch_api_request("https://api.twitch.tv/helix/content_classification_labels")->then() {
			array ccls = __ARGS__[0]->data;
			G->G->ccl_names = mkmapping(ccls->id, ccls->name); //NOTE: This includes MatureGame as it's used for viewership warnings.
			ccl_options = filter(ccls) {return __ARGS__[0]->id != "MatureGame";};
		};
	}
	::create(name);
}
