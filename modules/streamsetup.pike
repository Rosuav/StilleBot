inherit builtin_command;
inherit annotated;

//TODO: Document the fact that tags and CCLs can be added to with "+tagname" and removed
//from with "-tagname". It's a useful feature but hard to explain compactly.

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

continue mapping|Concurrent.Future message_params(object channel, mapping person, array param) {
	string token = yield((mixed)token_for_user_id_async(channel->userid))[0];
	if (token == "") error("Need broadcaster permissions\n");
	mapping prev = yield(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
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
						array ccls = yield(twitch_api_request("https://api.twitch.tv/helix/content_classification_labels"))->data;
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
		mapping ret = yield(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": params, "return_errors": 1]),
		));
		if (ret->error) error(ret->error + ": " + ret->message + "\n");
		now = yield(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
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
