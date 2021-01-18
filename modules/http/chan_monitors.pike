inherit http_endpoint;
inherit websocket_handler;

constant css_attributes = "font fontsize color css";

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
			"text": info ? req->misc->channel->expand_variables(info->text) : "Unknown monitor",
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
		}
		if (body->text == "") m_delete(cfg->monitors, nonce);
		else {
			mapping info = cfg->monitors[nonce] = (["text": body->text]);
			//TODO: Validate the individual values?
			foreach (css_attributes / " ", string key) if (body[key]) info[key] = body[key];
		}
		persist_config->save();
		string sample;
		if (cfg->monitors[nonce]) {
			sample = req->misc->channel->expand_variables(cfg->monitors[nonce]->text);
			array group = websocket_groups[nonce + req->misc->channel->name];
			if (group) (group - ({0}))->send_text(Standards.JSON.encode(cfg->monitors[nonce] | (["cmd": "update", "text": sample])));
		}
		return (["data": Standards.JSON.encode(([
				"nonce": nonce,
				"text": cfg->monitors[nonce],
				"sample": sample,
			])),
			"type": "application/json",
		]);
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render_template("chan_monitors.md", ([
		"channame": Standards.JSON.encode(req->misc->channel->name[1..]),
		"monitors": Standards.JSON.encode(cfg->monitors || ([]), 4),
		"css_attributes": css_attributes,
	]) | req->misc->chaninfo);
}

void update_text(mapping(string:mixed) conn)
{
	sscanf(conn->group || "", "%s#%s", string nonce, string chan);
	if (!nonce || !chan) return;
	object channel = G->G->irc->channels["#" + chan];
	if (!channel || !channel->config->monitors) return;
	mapping text = channel->config->monitors[nonce];
	if (!text) return;
	conn->sock->send_text(Standards.JSON.encode(text | (["cmd": "update", "text": channel->expand_variables(text->text)])));
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg) return;
	if (msg->cmd == "refresh" || msg->cmd == "init") update_text(conn);
}

protected void create(string name) {::create(name);}
