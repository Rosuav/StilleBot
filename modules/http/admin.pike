//Local admin actions eg message sending
//Unauthenticated, but can only be used from localhost
inherit http_websocket;

mapping handle_send_message(mapping body, object req) {
	if (!body->channel || !body->msg) return 0;
	object channel = G->G->irc->channels[body->channel];
	if (!channel) return (["error": 400, "data": "Only to bot-managed channels"]);
	//if (!stringp(body->msg)) return (["error": 400, "data": "Only simple string messages for now"]); //Totally unvalidated. Use with caution. Recommendation: Validate using the command editor first.
	channel->send((["user": "admin-poke"]), body->msg);
	return (["data": "Sent"]);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	//These tools are only available from localhost and maybe the local network.
	if (!NetUtils.is_local_host(req->get_ip()) && !has_prefix(req->get_ip(), "192.168.")) return (["error": 401, "data": "Nope"]);
	if (req->request_type == "POST") {
		catch { //Any sort of error, just return a nope
			mixed body = Standards.JSON.decode(utf8_to_string(req->body_raw || ""));
			function f = mappingp(body) && this["handle_" + body->cmd];
			mapping ret = f && f(body, req);
			if (ret) return ret;
		};
	} else if (req->request_type == "OPTIONS" || req->request_type == "HEAD") {
		return ([
			"data": "",
			"extra_heads": (["Access-Control-Allow-Headers": "Access-Control-Allow-Origin"]),
		]);
	} else if (string host = req->variables->factory) switch (host) {
		case "": case "sikorsky": {
			//Fetch a local save file
			string dir = "/home/rosuav/.steam/steam/steamapps/compatdata/526870/pfx/drive_c/users/steamuser/Local Settings/Application Data/FactoryGame/Saved/SaveGames/76561198043731689/";
			array files = glob("*.sav", get_dir(dir));
			array times = file_stat((dir + files[*])[*])->mtime;
			sort(times, files);
			return ([
				"file": Stdio.File(dir + files[-1]),
				"extra_heads": (["Pragma": "no-cache"]),
			]);
		}
		case "raptor": {
			//Fetch from Raptor via SSH. Not working. Don't understand it.
			werror("Sending from Raptor\n");
			return Concurrent.Promise() {
				Stdio.File pipe = Stdio.File();
				string data = "";
				pipe->set_read_callback() {data += __ARGS__[1];};
				Process.create_process(({"ssh", "F-22Raptor", "pike", "fetch.pike"}), ([
					"stdout": pipe->pipe(Stdio.PROP_IPC|Stdio.PROP_NONBLOCK),
					"callback": lambda(object proc) {if (proc->status() == 2) call_out(__ARGS__[0], 0, (["data": data]));},
				]));
			};
		}
	} else if (string game = req->variables->kerbal) switch (game) {
		case "": { //Pick the most recent persistent.sfs
			string dir = "/home/rosuav/.steam/steam/steamapps/common/Kerbal Space Program/saves";
			array dirs = get_dir(dir);
			array times = map(dirs) {
				object stat = file_stat(sprintf("%s/%s/persistent.sfs", dir, __ARGS__[0]));
				return stat->?mtime; //automap doesn't handle ->? the way I want it to
			};
			sort(times, dirs);
			return (["file": Stdio.File(sprintf("%s/%s/persistent.sfs", dir, dirs[-1]))]);
		}
		default: break; //TODO: Allow selection of a specific save file? Maybe?
	}
	return (["error": 403, "data": "Nope"]);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!NetUtils.is_local_host(conn->remote_ip)) return "You're not me, I'm not you";
}

mapping get_state(string group) {
	return ([]);
}
