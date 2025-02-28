inherit http_endpoint;
inherit enableable_module;

//To make cooperative subtriggers work, we'll need something like the way triggers are done.
constant ENABLEABLE_FEATURES = ([
	"songannounce": ([
		"description": "Announce songs in chat (see VLC integration)", "_hidden": 1,
		"special": "!musictrack",
		"fragment": "#!musictrack/",
		"response": (["delay": 2, "message": ([
			"conditional": "string", "expr1": "$vlcplaying$", "expr2": "1",
			"message": "SingsNote Now playing: {track} ({block}) SingsNote",
			"otherwise": ""
		])]),
	]),
	"raidshield": ([
		"description": "Alert incoming raiders if they're still broadcasting",
		"special": "!raided",
		"fragment": "#!raided/",
		"response": ([
			"delay": 60,
			"message": ([
				"builtin": "nowlive",
				"builtin_param": ({"$$"}),
				"message": ([
					"casefold": "",
					"conditional": "string",
					"expr1": "{channellive}",
					"expr2": "offline",
					"message": "",
					"otherwise": ([
						"dest": "/w",
						"message": "SirShield twitchRaid Hi! It looks like you're possibly still broadcasting. If that's not your intention, it may be worth checking your streaming software (eg OBS, StreamLabs Desktop, Xsplit, etc) to see if it has shut down. SirShield twitchRaid This is an automated message from the Mustard Mine Raid Shield. Feel free to reply to this whisper with any questions.",
						"target": "$$",
					]),
				]),
			]),
		]),
	]),
]);

//Note that, unlike regular trigger IDs, these indices are not intrinsic and can change. -1 indicates not present.
int get_trig_index(object channel, string kwd) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return 0;
	echoable_message response = channel->commands[info->special];
	if (!response) return -1;
	info = info->response;
	if (info->delay) info = info->message; 
	foreach (Array.arrayify(response); int i; echoable_message trig) {
		if (mappingp(trig) && trig->delay) trig = trig->message; //You can set whatever delay you like and it doesn't affect detection.
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
	array response = Array.arrayify(channel->commands[info->special]) + ({ });
	int idx = get_trig_index(channel, kwd);
	if (idx == -1 && !state) return; //Not present, not wanted, nothing to do
	if (idx == -1) response += ({info->response});
	else response[idx] = state ? info->response : "";
	response -= ({""});
	G->G->update_command(channel, "!!", info->special, response);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_specials.md", ([
			"loadingmsg": "Restricted to moderators only",
		]) | req->misc->chaninfo);
	}
	multiset scopes = (multiset)(token_for_user_login(req->misc->channel->name[1..])[1] / " ");
	int is_bcaster = req->misc->channel->userid == (int)req->misc->session->user->id;
	foreach (G->G->cmdmgr->SPECIALS, [string spec, [string desc, string originator, string params], string tab]) {
		array scopesets = G->G->SPECIALS_SCOPES[spec - "!"];
		string|zero scopes_required = 0;
		if (scopesets) {
			scopes_required = is_bcaster ? scopesets[0] * " " : "bcaster";
			foreach (scopesets, array scopeset)
				if (!has_value(scopes[scopeset[*]], 0)) scopes_required = 0;
		}
		commands += ({([
			"id": spec,
			"desc": desc, "originator": originator,
			"params": params, "tab": tab,
			//Null if none needed or we already have them. "bcaster" if scopes needed and we're not the broadcaster.
			//Otherwise, is the scopes required to activate this special.
			"scopes_required": scopes_required,
		])});
	}
	return render_template("chan_specials.md", ([
		"vars": ([
			"commands": commands,
			"SPECIAL_PARAMS": mkmapping(@Array.transpose(G->G->cmdmgr->SPECIAL_PARAMS)),
			"ws_type": "chan_commands", "ws_group": "!!" + req->misc->channel->name, "ws_code": "chan_specials",
		]) | G->G->command_editor_vars(req->misc->channel),
		"loadingmsg": "Loading...",
		"save_or_login": "[Save all](:#saveall)",
	]) | req->misc->chaninfo);
}

protected void create(string name) {::create(name);}
