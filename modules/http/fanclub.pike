inherit http_websocket;
inherit hook;

constant markdown = #"# Fan club

<style>
button {padding: 0;}
img.avatar {max-width: 40px;}
tr.selected {background: #fa7;}
</style>
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string|void club) {
	if (!club) club = req->variables->club; //Can go to /fanclub/X or /fanclub?club=X
	if (!club) return render(req, ([]));
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[club];
	if (!cfg) return render(req, ([]));
	get_users_info(cfg->members); //Fire off a query so they're more likely to be loaded by the time the websocket asks for them
	return render(req, ([
		"vars": (["ws_group": club]),
		//"owner": await(get_user_info(cfg->owner)), //Give better info if owner?
	]));
}

__async__ mapping get_state(string|int group) {
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[group];
	if (!cfg) return ([]);
	return ([
		"members": await(get_users_info(cfg->members)),
	]);
}

__async__ void websocket_cmd_join(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("JOIN! %O\n", msg);
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_remove(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Will handle both "remove self" and "kick user", where the latter is valid only for the owner
	werror("REMOVE! %O\n", msg);
	send_updates_all(conn->group);
}

protected void create(string name) {::create(name);}
