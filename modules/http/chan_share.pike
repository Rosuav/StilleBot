//Art share! Upload a file and the bot will post a link to it in chat.

inherit http_websocket;
inherit builtin_command;
inherit hook;
constant markdown = #"# Share your creations with $$channel$$

Uploading is permitted for: <ul id=user_types></ul>

### Your files

Please note: Files are removed periodically; this is not a portfolio.

<div id=uploads></div>
<form>Upload new file: <input type=file multiple accept=\"image/*\"></form>

<div id=errormsg></div>

> ### Delete file
> Really delete this file?
>
> [...](...)
>
> <div class=thumbnail></div>
>
> This file will be deleted after a day anyway, but if you wish to remove<br>
> it sooner, deleting it will immediately make it unavailable.
>
> [Delete](:#delete) [Cancel](:.dialog_close)
{: tag=dialog #confirmdeletedlg}

<style>
#errormsg {
	display: none;
	border: 2px solid red;
	background-color: #fdd;
	padding: 5px;
	margin: 10px;
}
#errormsg.visible {
	display: block;
}

#user_types {
	display: flex;
	list-style-type: none;
}
#user_types li {
	margin: 0 5px;
}
#user_types.nonmod li {
	border: 1px solid black;
	padding: 2px;
}
#user_types.nonmod li:not(.permitted) {
	display: none;
}
</style>
";

constant MAX_PER_FILE = 15, MAX_FILES = 4; //MB and file count. Larger than the alertbox limits since these files are ephemeral.
constant user_types = ({
	//Keyword, label, description
	({"mod", "Mods", "The broadcaster and channel moderators"}),
	({"vip", "VIPs", "Anyone with a gem badge in the channel"}),
	({"raider", "Raiders", "Other broadcasters who have raided the channel this stream"}),
	//TODO: !permit command, which will work via a builtin that grants temp permission
	({"all", "Anyone", "Anyone is allowed, any time"}),
});

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (mapping resp = ensure_login(req)) return resp;
	mapping cfg = persist_status->path("artshare", (string)req->misc->channel->userid, (string)req->misc->session->user->id);
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (!req->variables->id) return jsonify((["error": "No file ID specified"]));
		int idx = search((cfg->files || ({ }))->id, req->variables->id);
		if (idx < 0) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		mapping file = cfg->files[idx];
		if (file->url) return jsonify((["error": "File has already been uploaded"]));
		if (sizeof(req->body_raw) > MAX_PER_FILE * 1048576) return jsonify((["error": "Upload exceeds maximum file size"]));
		string mimetype;
		//TODO: ffprobe
		if (!mimetype) {
			Stdio.append_file("artshare.log", sprintf(#"Unable to ffprobe file art-%s
Channel: %s
Beginning of file: %O
FFProbe result: %O
Upload time: %s
-------------------------
", file->id, req->misc->channel->name, req->body_raw[..64], "(unimpl)", ctime(time())[..<1]));
			return jsonify((["error": "File type unrecognized. If it should have been supported, contact Rosuav and quote ID art-" + file->id]));
		}
		string filename = sprintf("%d-%s", req->misc->channel->userid, file->id);
		Stdio.write_file("httpstatic/artshare/" + filename, req->body_raw);
		file->url = sprintf("%s/static/share-%s", persist_config["ircsettings"]->http_address, filename);
		persist_status->path("share_metadata")[filename] = (["mimetype": mimetype]);
		persist_status->save();
		update_one("control" + req->misc->channel->name, file->id); //Display connection doesn't need to get updated.
		return jsonify((["url": file->url]));
	}
	return render(req, ([
		"vars": (["ws_group": (string)req->misc->session->user->id,
			"maxfilesize": MAX_PER_FILE, "maxfiles": MAX_FILES,
			"user_types": user_types, "is_mod": req->misc->is_mod,
		]),
	]) | req->misc->chaninfo);
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	mapping settings = persist_status->path("artshare", (string)channel->userid, "settings");
	if (id) {
		if (!cfg->files) return 0;
		int idx = search(cfg->files->id, id);
		return idx >= 0 && cfg->files[idx];
	}
	return (["items": cfg->files || ({ }),
		"who": settings->who || ([]),
	]);
}

void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	if (!cfg->files) cfg->files = ({ });
	if (!intp(msg->size) || msg->size < 0) return; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	string error;
	if (msg->size > MAX_PER_FILE * 1048576)
		error = "File too large (limit " + MAX_PER_FILE + " MB)";
	else if (sizeof(cfg->files) >= MAX_FILES)
		error = "Limit of " + MAX_FILES + " files reached. Delete other files to make room.";
	if (error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "uploaderror", "name": msg->name, "error": error]), 4));
		return;
	}
	string id;
	while (has_value(cfg->files->id, id = "share-" + String.string2hex(random_string(14))))
		; //I would be highly surprised if this loops at all, let alone more than once
	cfg->files += ({([
		"id": id, "name": msg->name,
		"uploaded": time(),
	])});
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	if (!cfg->files) return; //No files, can't delete
	int idx = search(cfg->files->id, msg->id);
	if (idx == -1) return; //Not found.
	mapping file = cfg->files[idx];
	cfg->files = cfg->files[..idx-1] + cfg->files[idx+1..];
	string fn = sprintf("%d-%s", channel->userid, file->id);
	rm("httpstatic/artshare/" + fn); //If it returns 0 (file not found/not deleted), no problem
	m_delete(persist_status->path("share_metadata"), fn);
	persist_status->save();
	update_one(conn->group, file->id);
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, "settings");
	//foreach ("foo bar spam ham" / " ", string key)
	//	if (stringp(msg[key])) cfg[key] = msg[key];
	if (mappingp(msg->who)) {
		if (!cfg->who) cfg->who = ([]);
		werror("WHO: %O\n", msg->who);
		foreach (user_types, array user) {
			mixed perm = msg->who[user[0]];
			werror("WHO %O: %O\n", user[0], perm);
			if (!undefinedp(perm)) cfg->who[user[0]] = !!perm;
		}
		werror("NOW WHO: %O\n", cfg->who);
	}
	persist_status->save();
	//NOTE: We don't actually update everyone when these change.
	//It's going to be unusual, and for non-mods, it's just a courtesy note anyway.
	send_updates_all(conn->group);
}

constant builtin_name = "Permit Art Share";
constant builtin_description = "Permit a user to share their art (one upload within 2 minutes)";
constant builtin_param = ({"User"});
constant vars_provided = ([
	"{error}": "Error message, if any",
]);

mapping message_params(object channel, mapping person, array|string param)
{
	string user;
	if (arrayp(param)) [user] = param;
	else sscanf(param, "%s %*s", user);
	mapping cfg = persist_status->path("artshare", (string)channel->userid, "settings");
	//TODO: Flag the user as temporarily permitted
	//TODO: Revoke temporary permission after 2 minutes or one upload
	return (["{error}": ""]);
}

protected void create(string name) {::create(name);}
