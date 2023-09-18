inherit http_websocket;
inherit hook;
inherit builtin_command;

constant builtin_name = "Monitors"; //The front end may redescribe this according to the parameters
constant builtin_description = "Get information about a channel monitor";
constant builtin_param = ({"/Monitor/monitor_id", "Advance by"});
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{type}": "Monitor type (text, goalbar, countdown)",
	//NOTE: Any values not applicable to the type in question will be blank/omitted.
	"{goal}": "Goal bar: Next goal as shown on screen",
	"{goal_raw}": "Goal bar: Next goal in raw numeric form (eg cents)",
	"{distance}": "Goal bar: Distance to next goal (negative if goal exceeded)",
	"{distance_raw}": "Goal bar: Distance in raw numeric form",
	"{value}": "Goal bar: Current value as shown (distance since the last tier reset)",
	"{value_raw}": "Goal bar: Current value in raw numeric form",
	"{percentage}": "Goal bar: Percentage of bar filled (can be above 100) as decimal number",
	"{tier}": "Goal bar: Current tier number (always 1 for non-tiered goals)",
]);

//Some of these attributes make sense only with certain types (eg needlesize is only for goal bars).
constant saveable_attributes = "previewbg barcolor fillcolor needlesize thresholds progressive lvlupcmd format width height "
	"active bit sub_t1 sub_t2 sub_t3 tip follow kofi_dono kofi_member kofi_renew kofi_shop" / " " + TEXTFORMATTING_ATTRS;
constant valid_types = (<"text", "goalbar", "countdown">);

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
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		if (!body || !mappingp(body) || !stringp(body->text)) return (["error": 400]);
		if (req->misc->session->fake) return jsonify((["ok": 1]));
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
					mapping vars = persist_status->has_path("variables", req->misc->channel->name) || ([]);
					void tryvar(string v) {if (!vars["$"+v+"$"]) body->varname = v;}
					for (int i = 0; i < 26 && !body->varname; ++i) tryvar(sprintf("goalbar%c", 'A' + i));
					for (int i = 0; i < 26*26 && !body->varname; ++i) tryvar(sprintf("goalbar%c%c", 'A' + i / 26, 'A' + i % 26));
					//Do I need to attempt goalbarAAA ? We get 700 options without, or 18K with.
					req->misc->channel->set_variable(body->varname, "0", "set");
				}
				//Apply some defaults where not provided.
				body = ([
					"thresholds": "100",
					"color": "#005500",
					"barcolor": "#DDDDFF",
					"fillcolor": "#FFFF55",
					"previewbg": "#BBFFFF",
					"needlesize": "0.375",
				]) | body;
			}
		}
		mapping info = cfg->monitors[nonce] = (["type": "text", "text": body->text]);
		if (valid_types[body->type]) info->type = body->type;
		foreach (saveable_attributes, string key) if (body[key]) info[key] = body[key];
		if (info->needlesize == "") info->needlesize = "0";
		if (body->varname) info->text = sprintf("$%s$:%s", body->varname, info->text);
		textformatting_validate(info);
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
		if (req->misc->session->fake) return (["error": 204]);
		m_delete(cfg->monitors, nonce);
		persist_config->save();
		send_updates_all(req->misc->channel->name);
		return (["error": 204]);
	}
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

mapping _get_monitor(object channel, mapping monitors, string id) {
	mapping text = monitors[id];
	return text && text | (["id": id, "display": channel->expand_variables(text->text), "text_css": textformatting_css(text)]);
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
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	sscanf(msg->varname || "", "%[A-Za-z]", string var);
	if (var != "") channel->set_variable(var, "0", "set");
}

//Requires that the variable exist
void websocket_cmd_setvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	mapping vars = persist_status->has_path("variables", channel->name) || ([]);
	string prev = vars["$" + msg->varname + "$"];
	if (!prev) return;
	channel->set_variable(msg->varname, (string)(int)msg->val, "set");
}

@hook_allmsgs:
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

@hook_subscription:
int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type == "subbomb") return 0; //Sometimes sub bombs come through AFTER their constituent parts :( Safer to count the parts and skip the bomb.
	autoadvance(channel, person, "sub_t" + tier, qty);
}

//TODO: Have a builtin that allows any command/trigger/special to advance bars
//Otherwise, changing the variable won't trigger the level-up command.
void autoadvance(object channel, mapping person, string key, int weight) {
	foreach (channel->config->monitors || ([]); string id; mapping info) {
		if (info->type != "goalbar" || !info->active) continue;
		int advance = key == "" ? weight : weight * (int)info[key];
		if (!advance) continue;
		sscanf(info->text, "$%s$:%s", string varname, string txt);
		if (!txt) continue;
		echoable_message lvlup = channel->commands[info->lvlupcmd];
		int prevtier = lvlup && (int)message_params(channel, person, ({id}))["{tier}"];
		int total = (int)channel->set_variable(varname, advance, "add"); //Abuse the fact that it'll take an int just fine for add :)
		Stdio.append_file("subs.log", sprintf("[%s] Advancing %s goal bar by %O*%O = %d - now %d\n", channel->name, varname, key, weight, advance, total));
		if (advance > 0 && lvlup) {
			int newtier = (int)message_params(channel, person, ({id}))["{tier}"];
			while (prevtier++ < newtier) channel->send(person, lvlup, (["%s": (string)prevtier]));
		}
	}
}

string format_plain(int value) {return (string)value;}
string format_currency(int value) {
	if (!(value % 100)) return "$" + (value / 100);
	return sprintf("$%d.%02d", value / 100, value % 100);
}
string format_subscriptions(int value) {
	if (!(value % 500)) return (string)(value / 500);
	return sprintf("%.3f", value / 500.0);
}

mapping message_params(object channel, mapping person, array param) {
	string monitor = param[0];
	int advance = sizeof(param) > 1 && (int)param[1];
	mapping info = channel->config->monitors[?monitor];
	if (!monitor) return (["{error}": "Unrecognized monitor ID - has it been deleted?"]);
	switch (info->type) {
		case "goalbar": {
			if (advance) autoadvance(channel, person, "", advance);
			int pos = (int)channel->expand_variables(info->text); //The text starts with the variable, then a colon, so this will give us the current (raw) value.
			int tier, goal, found;
			foreach (info->thresholds / " "; tier; string th) {
				goal = (int)th;
				if (pos < goal) {
					found = 1;
					break;
				}
				else if (!info->progressive) pos -= goal;
			}
			if (!found) {
				//Beyond the last threshold. Some numbers may exceed normal
				//limits, eg percentage being above 100. Note that, for a
				//non-tiered goal bar, this simply means "goal is reached".
				if (!info->progressive) pos += goal; //Show that we're past the goal
			}
			int percent = (int)(pos * 100.0 / goal + 0.5), distance = goal - pos;
			function fmt = this["format_" + info->format] || format_plain;
			return ([
				"{type}": info->type,
				"{goal}": fmt(goal), "{goal_raw}": (string)goal,
				"{distance}": fmt(distance), "{distance_raw}": (string)distance,
				"{value}": fmt(pos), "{value_raw}": (string)pos,
				"{percentage}": fmt(percent), "{percentage_raw}": (string)percent,
				"{tier}": (string)(tier + 1),
			]);
		}
		case "countdown": return ([
			"{type}": info->type,
			//TODO
		]);
		default: return (["{type}": info->type]); //Should be "text".
	}
}

protected void create(string name) {
	::create(name);
	G->G->goal_bar_autoadvance = autoadvance;
}
