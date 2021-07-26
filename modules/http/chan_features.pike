inherit http_websocket;
constant markdown = #"# Feature management for channel $$channel$$

Features not enabled or disabled will be: <b id=defaultstate>(checking...)</b>

Feature name | Effect | Active?
-------------|--------|--------
(loading...) | - | -
{: #features}

$$save_or_login||$$
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
	]) | req->misc->chaninfo);
}

mapping _get_item(string id, mapping feat) {
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[id]) return 0;
	return ([
		"id": id, "desc": FEATUREDESC[id],
		"state": ({"default", "active", "inactive"})[feat[id]],
	]);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping feat = persist_config->path("channels", channel->name[1..], "features");
	if (id) return _get_item(id, feat);
	return (["items": _get_item(function_object(G->G->commands->features)->FEATURES[*][0][*], feat),
		"defaultstate": channel->config->allcmds ? "active": "inactive"]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (grp != "control" || !G->G->irc->channels["#" + chan]) return;
	mapping feat = persist_config->path("channels", chan, "features");
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[msg->id]) return;
	switch (msg->state) {
		case "active": feat[msg->id] = 1; break;
		case "inactive": feat[msg->id] = -1; break;
		case "default": m_delete(feat, msg->id); break;
		default: return;
	}
	persist_config->save();
	update_one(conn->group, msg->id);
	update_one("view#" + chan, msg->id);
}
