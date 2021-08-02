inherit http_endpoint;
inherit enableable_module;

//To make cooperative subtriggers work, we'll need something like the way triggers are done.
constant ENABLEABLE_FEATURES = ([
	"transcoding": ([
		"description": "Greet the new stream with an announcement of transcoding availability",
		"special": "!channelonline",
		"response": ([
			"builtin": "transcoding",
			"message": ([
				"conditional": "number",
				"expr1": "{uptime} < 600",
				"message": ([
					"conditional": "string",
					"expr1": "{qualities}",
					"message": "Welcome to the stream! View this stream in glorious {resolution}!",
					"otherwise": "Welcome to the stream! View this stream in glorious {resolution}! Or any of its other resolutions: {qualities}",
				]),
				"otherwise": "",
			]),
		])
	]),
]);

//Note that, unlike regular trigger IDs, these indices are not intrinsic and can change. -1 indicates not present.
int get_trig_index(object channel, string kwd) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return 0;
	echoable_message response = G->G->echocommands[info->special + channel->name];
	if (!response) return -1;
	info = info->response;
	foreach (Array.arrayify(response); int i; echoable_message trig) {
		if (mappingp(trig) && trig->builtin == info->builtin &&
			trig->conditional == info->conditional &&
			(trig->expr1||"") == (info->expr1||"") &&
			(trig->expr2||"") == (info->expr2||""))
				return i;
	}
	return -1;
}
int can_manage_feature(object channel, string kwd) {return get_trig_index(channel, kwd) >= 0 ? 2 : 1;}

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	//Hack: Call on the normal commands updater to add a trigger
	array response = Array.arrayify(G->G->echocommands[info->special + channel->name]) + ({ });
	int idx = get_trig_index(channel, kwd);
	if (idx == -1 && !state) return; //Not present, not wanted, nothing to do
	if (idx == -1) response += ({info->response});
	else response[idx] = state ? info->response : "";
	response -= ({""});
	if (!sizeof(response)) //Nothing left? Delete the trigger altogether.
		G->G->websocket_types->chan_commands->websocket_cmd_delete(
			(["group": "!!" + channel->name]),
			(["cmdname": info->special])
		);
	else
		G->G->websocket_types->chan_commands->websocket_cmd_update(
			(["group": "!!" + channel->name]),
			(["cmdname": info->special, "response": response])
		);
}
string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_specials.md", ([
			"loadingmsg": "Restricted to moderators only",
			"save_or_login": "",
		]) | req->misc->chaninfo);
	}
	object addcmd = function_object(G->G->commands->addcmd);
	foreach (addcmd->SPECIALS, [string spec, [string desc, string originator, string params], string tab])
		commands += ({(["id": spec + req->misc->channel->name, "desc": desc, "originator": originator, "params": params, "tab": tab])});
	return render_template("chan_specials.md", ([
		"vars": ([
			"commands": commands,
			"SPECIAL_PARAMS": mkmapping(@Array.transpose(addcmd->SPECIAL_PARAMS)),
			"ws_type": "chan_commands", "ws_group": "!!" + req->misc->channel->name, "ws_code": "chan_specials",
			"builtins": G->G->commands_builtins,
			"voices": req->misc->channel->config->voices || ([]),
		]),
		"loadingmsg": "Loading...",
		"save_or_login": "<input type=submit value=\"Save all\">",
	]) | req->misc->chaninfo);
}

protected void create(string name) {::create(name);}
