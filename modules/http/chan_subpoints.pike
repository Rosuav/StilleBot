inherit http_websocket;

constant markdown = #"# Subpoints trackers for $$channel$$

<style>input[type=number] {width: 4em;}</style>

Unpaid | Font | Goal | Options | Actions | Link
-------|------|------|---------|---------|--------
loading... | - | - | - | - | -
{:#trackers}

[Add tracker](:#add_tracker)

* Unpaid points (eg for a bot) can also be adjusted to correct for API errors
* Changing the font or options will require a refresh of the in-OBS page
* In-chat notifications add load to your OBS, but *might* improve reliability.
  Regardless of this setting, an event hook will be active, which may be sufficient.
";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (string nonce = req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		mapping info = cfg->subpoints[?nonce];
		if (!info) return 0; //If you get the nonce wrong, just return an ugly 404 page.
		string style = "";
		if (cfg->font && cfg->font != "")
			style = sprintf("@import url(\"https://fonts.googleapis.com/css2?family=%s&display=swap\");"
					"#points {font-family: '%s', sans-serif;}"
					"%s", Protocols.HTTP.uri_encode(cfg->font), cfg->font, style);
		if ((int)cfg->fontsize) style += "#points {font-size: " + (int)cfg->fontsize + "px;}";
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + req->misc->channel->name, "ws_code": "subpoints"]),
		]));
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render(req, (["vars": ([
		"ws_group": "",
	])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping trackers = channel->config->subpoints || ([]);
	//TODO: Ensure event hooks exist
	if (grp != "") return (["data": 0]); //TODO: Count the actual subpoints
	if (id) return trackers[id];
	array t = values(trackers); sort(t->created, t);
	return (["items": t]);
}

void websocket_cmd_create(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	if (!channel->config->subpoints) channel->config->subpoints = ([]);
	string nonce = replace(MIME.encode_base64(random_string(30)), (["/": "1", "+": "0"]));
	channel->config->subpoints[nonce] = (["id": nonce, "created": time()]);
	persist_config->save();
	send_updates_all(conn->group);
}

void websocket_cmd_save(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	//TODO
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	mapping cfg = channel->config->subpoints;
	if (cfg[?msg->id]) {
		m_delete(cfg, msg->id);
		persist_config->save();
		send_updates_all(conn->group);
	}
}

protected void create(string name)
{
	::create(name);
	//TODO: Set up event hooks
}
