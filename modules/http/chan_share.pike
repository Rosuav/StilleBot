//Art share! Upload a file and the bot will post a link to it in chat.

inherit http_websocket;
inherit builtin_command;
inherit hook;
constant markdown = #"# Share your creations with $$channel$$

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
</style>
";

constant MAX_PER_FILE = 15, MAX_FILES = 4; //MB and file count. Larger than the alertbox limits since these files are ephemeral.

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
		"vars": (["ws_group": (string)req->misc->session->user->id, "maxfilesize": MAX_PER_FILE, "maxfiles": MAX_FILES]),
	]) | req->misc->chaninfo);
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	mapping settings = persist_status->path("artshare", (string)channel->userid, "settings");
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
	])});
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	if (!cfg->files) return; //No files, can't delete
	int idx = search(cfg->files->id, msg->id);
	if (idx == -1) return; //Not found.
	mapping file = cfg->files[idx];
	cfg->files = cfg->files[..idx-1] + cfg->files[idx+1..];
	string fn = sprintf("%d-%s", channel->userid, file->id);
	rm("httpstatic/uploads/" + fn); //If it returns 0 (file not found/not deleted), no problem
	m_delete(persist_status->path("upload_metadata"), fn);
	int changed_alert = 0;
	if (file->url) 
		foreach (cfg->alertconfigs || ([]);; mapping alert)
			while (string key = search(alert, file->url)) {
				alert[key] = "";
				changed_alert = 1;
			}
	persist_status->save();
	update_one(conn->group, file->id);
	if (changed_alert) update_one(cfg->authkey + channel->name, file->id);
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid);
	foreach ("hostlist_command hostlist_format" / " ", string key)
		if (stringp(msg[key])) cfg[key] = msg[key];
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
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
	mapping cfg = persist_status->path("artshare", (string)channel->userid);
	//TODO: Flag the user as temporarily permitted
	//TODO: Revoke temporary permission after 2 minutes or one upload
	return (["{error}": ""]);
}

protected void create(string name) {::create(name);}
