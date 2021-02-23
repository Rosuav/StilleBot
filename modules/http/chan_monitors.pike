inherit http_endpoint;
inherit websocket_handler;

//Note that this also handles CookingForNoobs's run distance gauge, which may end up
//turning into a more generic gauge. This has a different set of attributes and a
//different admin front-end, but the viewing endpoint and API handling are shared.
constant css_attributes = "font fontweight fontsize color css whitespace previewbg barcolor fillcolor bordercolor borderwidth needlesize thresholds padvert padhoriz";

/* TODO: Join up three things and make them all behave more similarly.
1) The monitors page where things get configured
2) The monitor page where things get seen
3) The noobsrun configuration page

Plan: Have multiple websocket groups available.
* Master websocket that changes only when a monitor is added or removed
* One socket group for each monitor - group is the nonce.

In the view page, it'll be pretty simple: one socket, use the nonce as the group, update display in render().
In the config page, the default socket created by ws_sync will be the master. When it triggers a render, check
which monitors exist and create their DOM elements and websockets. Each of those, on render, will update the
display and the config for its corresponding element.
In noobsrun config, it should probably continue to support just one (for now, at least), but it needs to do the
config as well as the display. Shouldn't be too hard but will need to cope with different config. May actually
end up being folded right into the same code and handled as a plain monitors config.

Ultimate advantage: config changes will be instantly synchronized across multiple pages. Great if you're helping
someone set things up. Also, the preview will actually work, instead of mostly working with a few exceptions.
*/

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		string nonce = req->variables->view;
		mapping info;
		if (!cfg->monitors || !cfg->monitors[nonce]) nonce = 0;
		else info = cfg->monitors[nonce];
		return render_template("monitor.html", ([
			"display": info ? req->misc->channel->expand_variables(info->text) : "Unknown monitor",
			"nonce": Standards.JSON.encode(nonce + req->misc->channel->name),
		]));
	}
	if (req->request_type == "PUT") {
		//API handling.
		if (!req->misc->is_mod) return (["error": 401]); //JS wants it this way, not a redirect that a human would like
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body) || !stringp(body->text)) return (["error": 400]);
		if (!cfg->monitors) cfg->monitors = ([]);
		string nonce = body->nonce;
		if (!cfg->monitors[nonce]) {
			//The given nonce doesn't exist - or none was given. Create a new monitor.
			//Note that this is deliberately slightly shorter than the subpoints nonce
			//(by 4 base64 characters), to allow them to be distinguished for debugging.
			nonce = replace(MIME.encode_base64(random_string(27)), (["/": "1", "+": "0"]));
			call_out(send_updates_all, 0, req->misc->channel->name); //When we're done, tell everyone there's a new monitor
		}
		mapping info = cfg->monitors[nonce] = (["text": body->text]);
		//TODO: Validate the individual values?
		foreach (css_attributes / " ", string key) if (body[key]) info[key] = body[key];
		persist_config->save();
		//TODO: Move this all onto a websocket message rather than a PUT request, and
		//then just call a vanilla send_updates_all(), relying on get_state().
		string display = req->misc->channel->expand_variables(cfg->monitors[nonce]->text);
		send_updates_all(nonce + req->misc->channel->name, cfg->monitors[nonce] | (["display": display]));
		return jsonify((["ok": 1]));
	}
	if (req->request_type == "DELETE") {
		if (!req->misc->is_mod) return (["error": 401]); //JS wants it this way, not a redirect that a human would like
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body) || !stringp(body->nonce)) return (["error": 400]);
		string nonce = body->nonce;
		if (!cfg->monitors || !cfg->monitors[nonce]) return (["error": 404]);
		m_delete(cfg->monitors, nonce);
		persist_config->save();
		send_updates_all(req->misc->channel->name);
		return (["error": 204]);
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render_template("chan_monitors.md", (["vars": ([
		"ws_type": "chan_monitors", "ws_group": req->misc->channel->name,
		"css_attributes": css_attributes,
	])]) | req->misc->chaninfo);
}

mapping get_state(string group) {
	if (!stringp(group)) return 0;
	sscanf(group, "%s#%s", string nonce, string chan);
	if (!nonce || !chan) return 0;
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return 0;
	mapping monitors = channel->config->monitors || ([]);
	if (nonce == "") return (["monitors": monitors]); //Master group - lists all monitors. Gives details for convenience ONLY, is not guaranteed.
	mapping text = monitors[nonce];
	if (!text) return 0;
	return text | (["display": channel->expand_variables(text->text)]);
}

protected void create(string name) {::create(name); G->G->monitor_css_attributes = css_attributes;}
