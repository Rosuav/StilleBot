inherit http_websocket;
inherit builtin_command;
inherit annotated;

/* TODO maybe: Event signals from OBS

Will require some sort of special trigger or equivalent.

Page uses addEventListener to get the event, then passes it along to the bot

See https://github.com/obsproject/obs-browser?tab=readme-ov-file#available-events
*/

constant markdown = #"# OBS Studio Integration

To enable integration, add [this page](obs?key=loading :#obslink) to OBS as a browser source,
and in the properties, grant Page Permissions 'Advanced Access', and ensure that 'shutdown source
when not visible' is *not* selected. Note that the page itself has no visual content, and can be
placed on any scene.

Need to reset the key? [Reset key](:#resetkey) will disable any previous link and make a new one.
";

constant builtin_name = "OBS Studio";
constant builtin_description = "Manage OBS Studio";
constant builtin_param = ({"/Action/Get scene/Switch scene", "Parameter"});
constant vars_provided = ([
	"{scenename}": "Current scene name",
]);

@retain: mapping obsstudio_inflight_messages = ([]);
__async__ mapping send_obs_signal(object channel, mapping msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "obsstudio"));
	string grp = cfg->nonce + "#" + channel->userid;
	array socks = websocket_groups[grp] || ({ });
	if (!sizeof(socks)) error("Not connected to OBS");
	msg->key = String.string2hex(random_string(6));
	object prom = obsstudio_inflight_messages[msg->key] = Concurrent.Promise();
	socks->send_text(Standards.JSON.encode(msg, 4));
	return await(prom->future()->timeout(5)); //Five seconds should be enough for a response. Otherwise assume the other end is gone.
	//TODO: If anything goes wrong, m_delete the promise from inflight_messages
}

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	//TODO: If no client connected, immediate error
	switch (param[0]) {
		case "Get scene": {
			mapping info = await(send_obs_signal(channel, (["cmd": "get_scene"])));
			return (["{scenename}": (string)info->scenename]);
		}
		case "Switch scene": {
			mapping info = await(send_obs_signal(channel, (["cmd": "set_scene", "scenename": param[1]])));
			return (["{scenename}": (string)info->scenename]);
		}
		default: error("Unknown subcommand"); //Shouldn't happen if using the GUI to edit commands
	}
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "obsstudio"));
	if (string nonce = req->variables->key) {
		if (nonce != cfg->nonce) return 0;
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "obs"]),
			"styles": "",
			"title": "Mustard Mine-OBS integration",
		]));
	}
	if (!req->misc->is_mod) {
		if (req->misc->session->user) return render(req, req->misc->chaninfo | ([
			"notmodmsg": "You're logged in, but you're not a recognized mod. Please say something in chat so I can see your sword.",
			"blank": "",
			"notmod2": "Functionality on this page will be activated for mods (and broadcaster) only.",
		]));
		return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	}
	if (!cfg->nonce) {
		cfg->nonce = String.string2hex(random_string(8));
		G->G->DB->save_config(req->misc->channel->userid, "obsstudio", cfg);
		//Should we send_updates_all? It's unlikely there'll be any clients.
	}
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "obsstudio"));
	if (grp != "" && grp != cfg->nonce) return 0;
	if (grp == "") return ([
		"nonce": cfg->nonce,
	]);
	return ([]); //Not sure what, if anything, we need for the client page.
}

__async__ void wscmd_resetkey(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->group != "#" + channel->userid) return;
	string prevnonce;
	await(G->G->DB->mutate_config(channel->userid, "obsstudio") {
		prevnonce = __ARGS__[0]->nonce;
		__ARGS__[0]->nonce = String.string2hex(random_string(8));
	});
	send_updates_all(channel, "");
	//TODO: Kick anything from prevnonce so they aren't left hanging uselessly
}

__async__ void wscmd_logme(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "obsstudio"));
	if (conn->group != cfg->nonce + "#" + channel->userid) return;
	werror("OBS LOGME: %O\n", msg);
}

__async__ void wscmd_response(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "obsstudio"));
	if (conn->group != cfg->nonce + "#" + channel->userid) return;
	object prom = m_delete(obsstudio_inflight_messages, msg->key);
	if (!prom) return; //Other end has given up on us
	prom->success(msg);
}

protected void create(string name) {::create(name);}
