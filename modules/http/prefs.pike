inherit http_websocket;
constant markdown = #"# Preferences and configuration

<section id=prefs></section>

Coming Soon: a save button so you can make changes?

<style>
#prefs > section {
	margin: 0.75em 0;
}
.pref_unknown {display: flex;}
.pref_unknown textarea {margin-left: 0.5em;}
</style>
";

//As well as preferences, this contains user notifications. Currently there is only one:
//prefs->notif_perms[perm] = ({(["desc": desc, "reason": reason]), ...})
//  - perm is some Twitch permission scope eg "channel:read:hype_train"
//  - desc is a human-readable description of why this is needed
//  - reason is a machine-readable keyword or marker which can be identified by the module
//    that created this, to determine whether or not it is still needed.
//When a permission is given (as bcaster auth), all its notifs are suppressed.
//An empty array should be ignored and can always be safely removed.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": "n/a"]), //The real synchronization happens through the per-user prefs
	]));
}

string websocket_validate(mapping conn, mapping msg) {return conn->session->user->?id ? 0 : "Not logged in";}
mapping get_state(string group) {return (["info": "See Other"]);}

//Everything from here down should be looking at the user prefs, and may come from any page,
//not just /prefs.
void websocket_cmd_prefs_send(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->prefs_uid) return;
	mapping prefs = persist_status->path("userprefs", conn->prefs_uid);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "prefs_replace", "userid": (int)conn->prefs_uid, "prefs": prefs])));
}
void websocket_cmd_prefs_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->prefs_uid) return;
	mapping prefs = persist_status->path("userprefs", conn->prefs_uid);
	mapping changed = ([]);
	foreach (msg; string k; mixed v) {
		//Update individual keys, but in case something gets looped back, don't
		//nest prefs inside prefs.
		if (k == "cmd" || k == "prefs") continue;
		if (has_prefix(k, "notif_")) continue; //Notifications are managed separately.
		if (v == (!has_index(prefs, k) ? Val.null : prefs[k])) continue; //Setting to the same value
		changed[k] = v;
		if (v == Val.null) m_delete(prefs, k); else prefs[k] = v;
	}
	if (!sizeof(changed)) return;
	persist_status->save();
	update_user_prefs(conn->prefs_uid, changed);
}

void update_user_prefs(string|int userid, mapping changed) {
	array grp = websocket_groups[(string)userid];
	if (grp && sizeof(grp)) grp->send_text(Standards.JSON.encode((["cmd": "prefs_update", "prefs": changed])));
}

protected void create(string name) {
	::create(name);
	G->G->update_user_prefs = update_user_prefs;
}
