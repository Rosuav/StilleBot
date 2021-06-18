inherit http_websocket;

constant markdown = #"# Subpoints counter for $$channel$$

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
	mapping monitors = channel->config->monitors || ([]);
	if (grp != "") return (["data": 0]);
	if (id) return 0;
	return (["items": ({ })]);
}

void websocket_cmd_create(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
}

void websocket_cmd_save(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
}

protected void create(string name)
{
	::create(name);
}
