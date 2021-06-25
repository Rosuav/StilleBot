inherit http_websocket;

//Some of these attributes make sense only with certain types (eg needlesize is only for goal bars).
constant css_attributes = "font fontweight fontstyle fontsize color css whitespace previewbg barcolor "
	"fillcolor bordercolor borderwidth needlesize thresholds padvert padhoriz lvlupcmd format width height "
	"active bit sub_t1 sub_t2 sub_t3 tip follow";
constant valid_types = (<"text", "goalbar">);

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
			"vars": (["ws_type": ws_type, "ws_group": nonce + req->misc->channel->name, "ws_code": "monitor"]),
			"styles": "#display div {width: 33%;}#display div:nth-of-type(2) {text-align: center;}#display div:nth-of-type(3) {text-align: right;}",
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
			if (body->type == "goalbar") {
				//Hack: Create a new variable for a new goal bar.
				if (!body->varname) {
					mapping vars = persist_status->path("variables")[req->misc->channel->name] || ([]);
					void tryvar(string v) {if (!vars["$"+v+"$"]) body->varname = v;}
					for (int i = 0; i < 26 && !body->varname; ++i) tryvar(sprintf("goalbar%c", 'A' + i));
					for (int i = 0; i < 26*26 && !body->varname; ++i) tryvar(sprintf("goalbar%c%c", 'A' + i / 26, 'A' + i % 26));
					//Do I need to attempt goalbarAAA ? We get 700 options without, or 18K with.
					req->misc->channel->set_variable(body->varname, "0", "set");
				}
				body = (["thresholds": "100"]) | body; //Apply some defaults where not provided.
			}
		}
		mapping info = cfg->monitors[nonce] = (["type": "text", "text": body->text]);
		if (valid_types[body->type]) info->type = body->type;
		//TODO: Validate the individual values?
		foreach (css_attributes / " ", string key) if (body[key]) info[key] = body[key];
		if (body->varname) info->text = sprintf("$%s$:%s", body->varname, info->text);
		persist_config->save();
		send_updates_all(nonce + req->misc->channel->name);
		update_one(req->misc->channel->name, nonce);
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
	return render(req, (["vars": ([
		"ws_group": "",
		"css_attributes": css_attributes,
	])]) | req->misc->chaninfo);
}

mapping _get_monitor(object channel, mapping monitors, string id) {
	mapping text = monitors[id];
	return text && (["css": ""]) | text | (["id": id, "display": channel->expand_variables(text->text)]);
}
bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping monitors = channel->config->monitors || ([]);
	if (grp != "") return (["data": _get_monitor(channel, monitors, grp)]);
	if (id) return _get_monitor(channel, monitors, id);
	return (["items": _get_monitor(channel, monitors, sort(indices(monitors))[*])]);
}

//Can overwrite an existing variable
void websocket_cmd_createvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	sscanf(msg->varname || "", "%[A-Za-z]", string var);
	if (var != "") channel->set_variable(var, "0", "set");
}

//Requires that the variable exist
void websocket_cmd_setvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	mapping vars = persist_status->path("variables")[channel->name] || ([]);
	string prev = vars["$" + msg->varname + "$"];
	if (!prev) return;
	channel->set_variable(msg->varname, (string)(int)msg->val, "set");
}

int message(object channel, mapping person, string msg)
{
	mapping mon = channel->config->monitors;
	if (!mon || !sizeof(mon)) return 0;
	//TODO: Support other ways of recognizing donations
	if (person->user == "streamlabs") {
		sscanf(msg, "%*s just tipped $%d.%d!", int dollars, int cents);
		autoadvance(channel, person, "tip", 100 * dollars + cents);
	}
	if (person->bits) autoadvance(channel, person, "bit", person->bits);
}

int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	autoadvance(channel, person, "sub_t" + tier, qty);
}

//TODO: Have a builtin that allows any command/trigger/special to advance bars
//Otherwise, changing the variable won't trigger the level-up command.
void autoadvance(object channel, mapping person, string key, int weight) {
	foreach (channel->config->monitors || ([]); ; mapping info) {
		if (info->type != "goalbar" || !info->active) continue;
		int advance = key == "" ? weight : weight * (int)info[key];
		if (!advance) continue;
		sscanf(info->text, "$%s$:%s", string varname, string txt);
		if (!txt) continue;
		int total = (int)channel->set_variable(varname, advance, "add"); //Abuse the fact that it'll take an int just fine for add :)
		if (advance < 0) continue;
		//See if we've just hit a new tier.
		foreach (info->thresholds / " "; int tier; string th) {
			int nexttier = 100 * (int)th; //TODO: Don't offset if not currency
			if (total >= nexttier) {total -= nexttier; continue;}
			//This is the current tier. If we've only barely started it,
			//then we probably just hit this tier. (If tier is 0, we've
			//just broken positive after having a negative total.)
			if (total < advance) channel->send(person, G->G->echocommands[info->lvlupcmd + channel->name], (["%s": (string)tier]));
			break;
		}
	}
}

protected void create(string name)
{
	register_hook("all-msgs", message);
	register_hook("subscription", subscription);
	::create(name);
}
