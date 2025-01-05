inherit http_websocket;
inherit builtin_command;
inherit annotated;

constant markdown = #"# OBS Studio Integration

To enable integration, add [this page](obs?key=loading :#obslink) to OBS as a browser source,
and in the properties, grant Page Permissions 'Advanced Access', and ensure that 'shutdown source
when not visible' is *not* selected. Note that the page itself has no visual content, and can be
placed on any scene.

Need to reset the key? [Reset key](:#resetkey) will disable any previous link and make a new one.
";

constant builtin_name = "OBS Studio";
constant builtin_description = "Manage OBS Studio";
constant builtin_param = ({"/Action/Select scene/Get scene"});
constant vars_provided = ([
	"{scenename}": "Current scene name",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	//TODO: Poke a signal out to the local websocket
	return ([
	]);
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

protected void create(string name) {::create(name);}
