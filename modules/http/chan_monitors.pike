inherit http_endpoint;
inherit websocket_handler;

//(websocket_groups[channel] - ({0}))->send_text(Standards.JSON.encode(state));

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
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
		else cfg->monitors[nonce] = body->text;
		persist_config->save();
		return (["data": Standards.JSON.encode(([
				"nonce": nonce,
				"text": cfg->monitors[nonce],
				"sample": cfg->monitors[nonce] && req->misc->channel->expand_variables(cfg->monitors[nonce]),
			])),
			"type": "application/json",
		]);
	}
	if (!req->misc->is_mod) return redirect(".");
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render_template("chan_monitors.md", ([
		"monitors": Standards.JSON.encode(cfg->monitors || ([]), 4),
	]) | req->misc->chaninfo);
}

string get_text(mapping(string:mixed) conn)
{
	sscanf(conn->group || "", "%s#%s", string nonce, string chan);
	if (!nonce || !chan) return 0;
	object channel = G->G->irc->channels["#" + chan];
	if (!channel || !channel->config->monitors) return 0;
	string text = channel->config->monitors[nonce];
	if (!text) return 0;
	return channel->expand_variables(text);
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg) return;
	if (msg->cmd == "refresh" || msg->cmd == "init")
	{
		conn->sock->send_text(Standards.JSON.encode((["text": get_text(conn)])));
	}
}

protected void create(string name) {::create(name);}
