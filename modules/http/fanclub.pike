inherit http_websocket;

constant markdown = #"# $$clubtitle||Fan Club$$
{:#clubtitle}

$$managebtn||$$

<div id=members></div>

<style>
img.avatar {vertical-align: middle; margin-right: 4px;}
.members {
	display: flex;
	flex-wrap: wrap;
	justify-content: space-between;
	row-gap: 10px;
}
.member {
	width: 220px;
}
</style>

> ### Manage fan club
>
> <label>Club title: <input name=title size=30 value=\"$$clubtitle||$$\"></label>
>
> [Save](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #managedlg}
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string|void club) {
	if (!club) club = req->variables->club; //Can go to /fanclub/X or /fanclub?club=X
	if (!club) return render(req, ([]));
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[club];
	if (!cfg) return render(req, (["club": club]));
	get_users_info(cfg->members + ({cfg->owner})); //Fire off a query so they're more likely to be loaded by the time the websocket asks for them
	int(1bit) is_owner = 0;
	string uid = "0";
	if (mapping user = req->misc->session->?user) {
		is_owner = user->id == cfg->owner || is_localhost_mod(user->login, req->get_ip());
		uid = user->id;
	}
	return render(req, ([
		//QUIRK: If the title contains Markdown metacharacters, they will be initially parsed, then replaced when the socket connects.
		"clubtitle": cfg->title,
		"managebtn": is_owner ? "[Manage fan club](:.opendlg data-dlg=managedlg)" : "",
		"vars": (["ws_group": club, "logged_in_as": (int)uid]),
	]));
}

__async__ mapping get_state(string|int group) {
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[group];
	if (!cfg) return ([]);
	return ([
		"title": cfg->title,
		"members": await(get_users_info(cfg->members)),
		"owner": await(get_user_info(cfg->owner)),
	]);
}

__async__ void websocket_cmd_configure(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping user = conn->session->?user;
	if (!user) return; //Can't be the owner if you're not logged in.
	await(G->G->DB->mutate_config(0, "fanclubs") {
		mapping cfg = __ARGS__[0][conn->group];
		if (!cfg) return; //Shouldn't happen
		//CHECK: Are you the owner? Normally a non-owner won't even send this request, so I don't mind a bit of unnecessary DB traffic in that situation.
		if (user->id != cfg->owner && !is_localhost_mod(user->login, conn->remote_ip)) return;
		if (msg->title) cfg->title = msg->title;
	});
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_join(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping user = conn->session->?user;
	if (!user) return;
	await(G->G->DB->mutate_config(0, "fanclubs") {
		mapping cfg = __ARGS__[0][conn->group];
		if (!cfg) return; //Shouldn't happen
		if (!has_value(cfg->members, (int)user->id)) cfg->members += ({(int)user->id});
	});
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_remove(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Will handle both "remove self" and "kick user", where the latter is valid only for the owner
	mapping user = conn->session->?user;
	if (!user) return;
	await(G->G->DB->mutate_config(0, "fanclubs") {
		mapping cfg = __ARGS__[0][conn->group];
		if (!cfg) return; //Shouldn't happen
		int uid = (int)user->id;
		if (msg->removeuser && (user->id == cfg->owner || is_localhost_mod(user->login, conn->remote_ip)))
			//Owner override - may remove other users.
			uid = msg->removeuser;
		cfg->members -= ({uid});
	});
	send_updates_all(conn->group);
}

protected void create(string name) {
	::create(name);
	G->G->http_endpoints["/fanclub/%[^/]"] = http_request;
}
