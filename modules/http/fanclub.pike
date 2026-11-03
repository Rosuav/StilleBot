inherit http_websocket;

constant markdown = #"# $$clubtitle||Fan Club$$
{:#clubtitle}

$$clubdesc||$$

$$managebtn||$$

<div id=members></div>

> ### Update your status
>
> <label>Status: <input name=status size=30></label>
>
> [Save](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #statusdlg}

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
> <label>Club title: <input name=title size=30></label>
> <p><label>Description (Markdown allowed)<br><textarea name=description rows=8 cols=50></textarea></label></p>
>
> [Save](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #managedlg}
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string|void club) {
	if (!club) club = req->variables->club; //Can go to /fanclub/X or /fanclub?club=X
	if (!club) return render(req, ([]));
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[club];
	if (!cfg) return render(req, (["club": club]));
	int(1bit) is_owner = 0;
	string uid = "0";
	if (mapping user = req->misc->session->?user) {
		is_owner = user->id == cfg->owner || is_localhost_mod(user->login, req->get_ip());
		uid = user->id;
	}
	return render(req, ([
		//QUIRK: If the title contains Markdown metacharacters, they will be initially parsed, then replaced when the socket connects.
		"clubtitle": cfg->title, "clubdesc": cfg->description || "",
		"managebtn": is_owner ? "[Manage fan club](:.opendlg data-dlg=managedlg)" : "",
		"vars": (["ws_group": club, "logged_in_as": (int)uid]),
	]));
}

__async__ void check_users(string group, array uids) {
	array users = await(get_users_info(uids, "id"));
	int changed = 0;
	await(G->G->DB->mutate_config(0, "fanclubs") {mapping memb = __ARGS__[0][group]->members;
		foreach (users, mapping user) {
			mapping cur = memb[user->id];
			if (!cur) continue; //User no longer a member
			cur->_fetch_time = user->_fetch_time;
			foreach (({"login", "display_name", "profile_image_url"}), string key)
				if (cur[key] != user[key]) {changed = 1; cur[key] = user[key];}
		}
	});
	if (changed) send_updates_all(group);
}

__async__ mapping get_state(string|int group) {
	mapping cfg = await(G->G->DB->load_config(0, "fanclubs"))[group];
	if (!cfg) return ([]);
	//If any of the data is stale, requery; don't wait for it though, just give what we already have.
	//Note that we'll often consider the data stale but not get any actual changes, which will update
	//the fetch times but not push anything out to the end user.
	int cutoff = time() - 3600;
	array checkme = ({ });
	foreach (cfg->members; string id; mapping m) if (m->_fetch_time < cutoff) checkme += ({id});
	if (sizeof(checkme)) check_users(group, checkme);
	return ([
		"title": cfg->title, "description": cfg->description,
		"members": cfg->members,
		"owner": cfg->owner,
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
		if (msg->description) cfg->description = msg->description;
	});
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_join(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping user = conn->session->?user;
	if (!user) return;
	await(G->G->DB->mutate_config(0, "fanclubs") {
		mapping cfg = __ARGS__[0][conn->group];
		if (!cfg) return; //Shouldn't happen
		cfg->members[user->id] = (["joined": time(), "uid": user->id]);
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
		string uid = user->id;
		if (msg->removeuser && (user->id == cfg->owner || is_localhost_mod(user->login, conn->remote_ip)))
			//Owner override - may remove other users.
			uid = (string)msg->removeuser;
		m_delete(cfg->members, uid);
	});
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_set_status(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Ditto, also handles the owner removing a user's status
	mapping user = conn->session->?user;
	if (!user) return;
	await(G->G->DB->mutate_config(0, "fanclubs") {
		mapping cfg = __ARGS__[0][conn->group];
		if (!cfg) return; //Shouldn't happen
		string uid = user->id;
		if (msg->removeuser && (user->id == cfg->owner || is_localhost_mod(user->login, conn->remote_ip))) {
			//Owner override - may remove other users.
			uid = (string)msg->removeuser;
			msg->status = ""; //Owner may only clear a status, not set one
		}
		mapping memb = cfg->members[uid];
		if (!memb) return; //May have been kicked
		if (msg->status == "") m_delete(memb, "status");
		else memb->status = msg->status[..80]; //Limit it to a reasonable length
	});
	send_updates_all(conn->group);
}

protected void create(string name) {
	::create(name);
	G->G->http_endpoints["/fanclub/%[^/]"] = http_request;
}
