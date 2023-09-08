//Art share! Upload a file and the bot will post a link to it in chat.

inherit http_websocket;
inherit builtin_command;
inherit hook;
inherit annotated;
constant markdown = #"# Share your creations with $$channel$$

Uploading is permitted for: <ul id=user_types></ul>

Whenever a file gets uploaded, the bot will announce this in chat: <input id=msgformat size=50><br>
Example: <code id=defaultmsg></code>

### Your files

Please note: Files are removed periodically; this is not a portfolio.

<div id=uploads></div>
<form>Upload new file: <input type=file multiple accept=\"image/*\"></form>
<div class=filedropzone>Or drop files here to upload</div>

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
#user_types.nonmod input {display: none;}
#user_types.nonmod li:not(.permitted) {
	display: none;
}
#uploads {
	display: flex;
	flex-wrap: wrap;
}
#uploads > label {
	border: 1px solid black;
	margin: 1em;
	position: relative;
}
#uploads .confirmdelete {
	position: absolute;
	right: 0.5em; top: 0.5em;
	width: 20px; height: 23px;
	padding: 0;
}
.thumbnail {
	width: 150px; height: 150px;
	background: none center/contain no-repeat;
}
figcaption {
	max-width: 150px;
	overflow-wrap: break-word;
}
.filedropzone {
	left: 0; right: 0;
	height: 4em;
	border: 1px dashed black;
	background: #eeeeff;
	margin: 0 0.25em;
	padding: 0.5em;
}
</style>
";

constant DEFAULT_MSG_FORMAT = "New art share from {username}: {URL}";
constant MAX_PER_FILE = 15, MAX_FILES = 4; //MB and file count. Larger than the alertbox limits since these files are ephemeral.
constant user_types = ({
	//Keyword, label, description
	({"mod", "Mods", "The broadcaster and channel moderators"}),
	({"vip", "VIPs", "Anyone with a gem badge in the channel"}),
	({"raider", "Raiders", "Other broadcasters who have raided the channel this stream"}),
	//TODO: !permit command, which will work via a builtin that grants temp permission
	({"all", "Anyone", "Anyone is allowed, any time"}),
});

//Map the FFProbe results to their MIME types.
//If not listed, the file is unrecognized and will be rejected.
constant file_mime_types = ([
	//"apng": "image/apng"? "video/apng"? WHAT?!?
	"gif": "image/gif", "gif_pipe": "image/gif",
	"jpeg_pipe": "image/jpeg",
	"png_pipe": "image/png",
	"svg_pipe": "image/svg+xml",
	"matroska,webm": "video/webm",
]);

@retain: mapping artshare_messageid = ([]);

continue Concurrent.Future|string permission_check(object channel, int is_mod, mapping user) {
	mapping cfg = persist_status->path("artshare", (string)channel->userid, "settings");
	string scopes = persist_status->path("bcaster_token_scopes")[channel->name[1..]] || "";
	if (has_value(scopes / " ", "moderation:read")) { //TODO: How would we get this permission if we don't have it? Some sort of "Forbid banned users" action for the broadcaster?
		if (has_value(yield(get_banned_list(channel->userid))->user_id, user->id)) {
			//Should we show differently if there's an expiration on the timeout?
			return "You're currently unable to talk in that channel, so you can't share either - sorry!";
		}
	}
	mapping who = cfg->who || ([]);
	if (who->all) return 0; //Go for it!
	//Ideally, replace this error with something more helpful, based on who DOES have permission.
	//The order of these checks is important, as the last one wins on error messages.
	string error = "You don't have permission to share files here, sorry!";
	if (who->raider) {
		if (channel->raiders[(int)user->id]) return 0; //Raided any time this stream, all good.
		//No error message change here.
	}
	//if (who->permit) //TODO: If you've been given temp permission, return 0, else set error to "ask for a !permit before sharing"
	if (who->mod) {
		if (is_mod) return 0;
		error = "Moderators are allowed to share artwork. If you're a mod, please say something in chat so I can see your mod sword.";
	}
	if (who->vip) {
		mapping attrs = channel->user_attrs[(int)user->id];
		if (attrs->?badges->?vip) return 0;
		error = (who->mod ? "Mods and" : "Only") + " VIPs are allowed to share artwork. If you are such, please say something in chat so I can see your badge.";
	}
	return error;
}

continue Concurrent.Future|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (mapping resp = ensure_login(req)) return resp;
	mapping cfg = persist_status->path("artshare", (string)req->misc->channel->userid, (string)req->misc->session->user->id);
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (!req->variables->id) return jsonify((["error": "No file ID specified"]));
		int idx = search((cfg->files || ({ }))->id, req->variables->id);
		if (idx < 0) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		mapping file = cfg->files[idx];
		if (file->url) return jsonify((["error": "File has already been uploaded"]));
		if (sizeof(req->body_raw) > MAX_PER_FILE * 1048576) return jsonify((["error": "Upload exceeds maximum file size"]));
		if (string error = yield(permission_check(req->misc->channel, req->misc->is_mod, req->misc->session->user)))
			return jsonify((["error": error]));
		string filename = sprintf("%d-%s", req->misc->channel->userid, file->id);
		Stdio.write_file("httpstatic/artshare/" + filename, req->body_raw);
		string mimetype;
		mapping rc = Process.run(({"ffprobe", "httpstatic/artshare/" + filename, "-print_format", "json", "-show_format", "-v", "quiet"}));
		mixed raw_ffprobe = rc->stdout + "\n" + rc->stderr + "\n";
		if (!rc->exitcode) {
			catch {raw_ffprobe = Standards.JSON.decode(rc->stdout);};
			if (mappingp(raw_ffprobe)) mimetype = file_mime_types[raw_ffprobe->format->format_name];
		}
		if (!mimetype) {
			Stdio.append_file("artshare.log", sprintf(#"Unable to ffprobe file art-%s
Channel: %s
File size: %d
Beginning of file: %O
FFProbe result: %O
Upload time: %s
-------------------------
", file->id, req->misc->channel->name, sizeof(req->body_raw), req->body_raw[..64], raw_ffprobe, ctime(time())[..<1]));
			delete_file(req->misc->channel, req->misc->session->user->id, file->id);
			return jsonify((["error": "File type unrecognized. If it should have been supported, contact Rosuav and quote ID art-" + file->id]));
		}
		file->url = sprintf("%s/static/share-%s", persist_config["ircsettings"]->http_address, filename);
		persist_status->path("share_metadata")[filename] = (["mimetype": mimetype]);
		persist_status->save();
		update_one(req->misc->session->user->id + req->misc->channel->name, file->id);
		mapping cfg = persist_status->path("artshare", (string)req->misc->channel->userid, "settings");
		req->misc->channel->send(
			(["displayname": req->misc->session->user->display_name]),
			cfg->msgformat || DEFAULT_MSG_FORMAT,
			(["{URL}": file->url, "{sharerid}": req->misc->session->user->id, "{fileid}": file->id]),
		) {[mapping vars, mapping params] = __ARGS__;
			file->messageid = params->id; //If this has somehow already been deleted from persist, it won't matter; we'll save an unchanged persist mapping.
			persist_status->save();
			//Note that the channel ID isn't strictly necessary, as any deletion signal will
			//itself be associated with that channel; but it's nice to have for debugging.
			artshare_messageid[params->id] = ({(string)req->misc->channel->userid, vars["{sharerid}"], vars["{fileid}"]});
		};
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
		"msgformat": settings->msgformat,
		"defaultmsg": DEFAULT_MSG_FORMAT,
	]);
}

void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(upload(conn, msg));}
continue Concurrent.Future upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return 0;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, grp);
	if (!cfg->files) cfg->files = ({ });
	if (!intp(msg->size) || msg->size < 0) return 0; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	string error;
	if (string err = yield(permission_check(channel, conn->is_mod, conn->session->user)))
		error = err;
	else if (msg->size > MAX_PER_FILE * 1048576)
		error = "File too large (limit " + MAX_PER_FILE + " MB)";
	else if (sizeof(cfg->files) >= MAX_FILES)
		error = "Limit of " + MAX_FILES + " files reached. Delete other files to make room.";
	if (error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "uploaderror", "name": msg->name, "error": error]), 4));
		return 0;
	}
	string id;
	mapping meta = persist_status->path("share_metadata");
	while (meta[sprintf("%d-%s", channel->userid, id = "share-" + String.string2hex(random_string(14)))])
		; //I would be highly surprised if this loops at all, let alone more than once
	cfg->files += ({([
		"id": id, "name": msg->name,
		"uploaded": time(),
	])});
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id);
}

void delete_file(object channel, string userid, string fileid) {
	mapping cfg = persist_status->path("artshare", (string)channel->userid, userid);
	if (!cfg->files) return; //No files, can't delete
	int idx = search(cfg->files->id, fileid);
	if (idx == -1) return; //Not found.
	mapping file = cfg->files[idx];
	cfg->files = cfg->files[..idx-1] + cfg->files[idx+1..];
	string fn = sprintf("%d-%s", channel->userid, file->id);
	rm("httpstatic/artshare/" + fn); //If it returns 0 (file not found/not deleted), no problem
	m_delete(persist_status->path("share_metadata"), fn);
	persist_status->save();
	update_one(userid + channel->name, file->id);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return;
	delete_file(channel, grp, msg->id);
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake || !conn->is_mod) return;
	mapping cfg = persist_status->path("artshare", (string)channel->userid, "settings");
	foreach ("msgformat" / " ", string key)
		if (stringp(msg[key])) cfg[key] = msg[key];
	if (mappingp(msg->who)) {
		if (!cfg->who) cfg->who = ([]);
		foreach (user_types, array user) {
			mixed perm = msg->who[user[0]];
			if (!undefinedp(perm)) cfg->who[user[0]] = !!perm;
		}
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

@hook_deletemsg:
int delmsg(object channel, object person, string target, string msgid) {
	//If a mod removes the bot's message reporting the link, delete the file.
	array info = artshare_messageid[msgid];
	if (info) delete_file(channel, info[1], info[2]);
}

@hook_deletemsgs:
int delmsgs(object channel, object person, string target) {
	//If someone gets timed out or banned, delete all their files.
	mapping cfg = persist_status->path("artshare", (string)channel->userid)[target];
	foreach (cfg->?files || ({ }), mapping file) {
		delete_file(channel, target, file->id);
		//And delete the messages that announced them
		if (file->messageid) channel->send(([]), "/deletemsg " + file->messageid);
	}
}

void cleanup() {
	if (mixed co = m_delete(G->G, "artshare_cleanup")) remove_call_out(co);
	mapping meta = persist_status->path("share_metadata");
	mapping artshare = persist_status->path("artshare");
	int old = time() - 86400; //Max age
	array chans = values(G->G->irc->channels);
	foreach (artshare; string channelid; mapping configs) {
		//First, find the right channel object.
		int idx = search(chans->userid, (int)channelid);
		if (idx < 0) continue; //Are we still loading, or is this a deleted channel? Hard to know.
		object channel = chans[idx];
		foreach (configs; string userid; mapping cfg) {
			if (!(int)userid) continue; //Not a user ID (probably the word "settings")
			if (cfg->files) foreach (cfg->files, mapping file) {
				if (file->uploaded >= old) continue; //Mmmm, still fresh!
				//This file is old. Dispose of it. Eww.
				delete_file(channel, userid, file->id);
			}
		}
	}
	//Note: It is possible for upload permission to be requested, but the upload
	//not happen, which would leave entries in the channel+user file list, but
	//nothing in meta. This is only a problem if there are actually no files at
	//all that have been fully uploaded.
	if (sizeof(meta)) G->G->artshare_cleanup = call_out(cleanup, 3600 * 12); //Check twice a day for anything over a day old
}

protected void create(string name) {
	::create(name);
	cleanup();
}
