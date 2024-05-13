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
	height: 4em;
}
</style>
";

constant DEFAULT_MSG_FORMAT = "New art share from {username}: {URL}";
constant MAX_PER_FILE = 16, MAX_FILES = 4; //MB and file count. File size is advisory, upload.pike has the hard limit.
constant user_types = ({
	//Keyword, label, description
	({"mod", "Mods", "The broadcaster and channel moderators"}),
	({"vip", "VIPs", "Anyone with a gem badge in the channel"}),
	({"raider", "Raiders", "Other broadcasters who have raided the channel this stream"}),
	//TODO: !permit command, which will work via a builtin that grants temp permission
	({"all", "Anyone", "Anyone is allowed, any time"}),
});

@retain: mapping artshare_messageid = ([]);
@retain: mapping artshare_file_messageid = ([]); //Map a UUID for a file to the corresponding message ID

__async__ string permission_check(object channel, int is_mod, mapping user) {
	mapping settings = await(G->G->DB->load_config(channel->userid, "artshare"));
	string scopes = token_for_user_id(channel->userid)[1];
	if (has_value(scopes / " ", "moderation:read")) { //TODO: How would we get this permission if we don't have it? Some sort of "Forbid banned users" action for the broadcaster?
		if (has_value(await(get_banned_list(channel->userid))->user_id, user->id)) {
			//Should we show differently if there's an expiration on the timeout?
			return "You're currently unable to talk in that channel, so you can't share either - sorry!";
		}
	}
	mapping who = settings->who || ([]);
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
		if (!channel->user_badges[(int)user->id]->?vip) return 0;
		error = (who->mod ? "Mods and" : "Only") + " VIPs are allowed to share artwork. If you are such, please say something in chat so I can see your badge.";
	}
	return error;
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (mapping resp = ensure_login(req)) return resp;
	return render(req, ([
		"vars": (["ws_group": (string)req->misc->session->user->id,
			"maxfilesize": MAX_PER_FILE, "maxfiles": MAX_FILES,
			"user_types": user_types, "is_mod": req->misc->is_mod,
		]),
	]) | req->misc->chaninfo);
}

__async__ void file_uploaded(int channelid, mapping user, mapping file) {
	update_one(user->id + "#" + channelid, file->id);
	mapping settings = await(G->G->DB->load_config(channelid, "artshare"));
	G->G->irc->id[channelid]->send(
		(["displayname": user->display_name]),
		settings->msgformat || DEFAULT_MSG_FORMAT,
		(["{URL}": file->metadata->url, "{sharerid}": user->id, "{fileid}": file->id]),
	) {[mapping vars, mapping params] = __ARGS__;
		//Note that the channel ID isn't strictly necessary, as any deletion signal will
		//itself be associated with that channel; but it's nice to have for debugging.
		artshare_messageid[params->id] = ({(string)channelid, vars["{sharerid}"], vars["{fileid}"]});
		artshare_file_messageid[vars["{fileid}"]] = params->id;
	};
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping settings = await(G->G->DB->load_config(channel->userid, "artshare"));
	if (id) {
		array files = await(G->G->DB->list_ephemeral_files(channel->userid, grp, id));
		return sizeof(files) && files[0];
	}
	array files = await(G->G->DB->list_ephemeral_files(channel->userid, grp));
	return (["items": files,
		"who": settings->who || ([]),
		"msgformat": settings->msgformat,
		"defaultmsg": DEFAULT_MSG_FORMAT,
	]);
}

__async__ void wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!intp(msg->size) || msg->size < 0) return 0; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	string error;
	if (string err = await(permission_check(channel, conn->is_mod, conn->session->user)))
		error = err;
	else if (msg->size > MAX_PER_FILE * 1048576)
		error = "File too large (limit " + MAX_PER_FILE + " MB)";
	else if (sizeof(await(G->G->DB->list_ephemeral_files(channel->userid, conn->session->user->id))) >= MAX_FILES)
		error = "Limit of " + MAX_FILES + " files reached. Delete other files to make room.";
	if (error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "uploaderror", "name": msg->name, "error": error]), 4));
		return;
	}
	string id = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, ([
		"name": msg->name,
		"size": msg->size,
	]), 1));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	//We kinda ought to push out an update with the half-uploaded file, but it's tidier to
	//leave it absent until the upload is complete.
	//update_one(conn->group, id);
}

__async__ void delete_file(object channel, string userid, string fileid) {
	array files = await(G->G->DB->purge_ephemeral_files(channel->userid, userid, fileid));
	if (sizeof(files)) {
		update_one(userid + "#" + channel->userid, fileid);
		if (string id = artshare_file_messageid[fileid]) channel->send(([]), "/deletemsg " + id);
	}
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake) return;
	delete_file(channel, grp, msg->id);
}

__async__ void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || conn->session->fake || !conn->is_mod) return; //TODO: Use wscmd_ once async functions can be annotated
	mapping settings = await(G->G->DB->load_config(channel->userid, "artshare"));
	foreach ("msgformat" / " ", string key)
		if (stringp(msg[key])) settings[key] = msg[key];
	if (mappingp(msg->who)) {
		if (!settings->who) settings->who = ([]);
		foreach (user_types, array user) {
			mixed perm = msg->who[user[0]];
			if (!undefinedp(perm)) settings->who[user[0]] = !!perm;
		}
	}
	await(G->G->DB->save_config(channel->userid, "artshare", settings));
	//NOTE: We don't actually update everyone when these change.
	//It's going to be unusual, and for non-mods, it's just a courtesy note anyway.
	send_updates_all(conn->group);
}

constant builtin_name = "Permit Art Share";
constant builtin_description = "Permit a user to share their art (one upload within 2 minutes)";
constant builtin_param = "User"; //what other args would be useful here?
constant vars_provided = ([]);

mapping message_params(object channel, mapping person, array param) {
	string user = param[0];
	//TODO: Flag the user as temporarily permitted
	//TODO: Revoke temporary permission after 2 minutes or one upload
	return ([]);
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
	G->G->DB->purge_ephemeral_files(channel->userid, target);
}

void cleanup() {
	remove_call_out(G->G->artshare_cleanup);
	G->G->artshare_cleanup = call_out(cleanup, 3600 * 12); //Check twice a day for anything over a day old
	G->G->DB->query_rw("delete from stillebot.uploads where expires < now() returning channel, uploader, id")->then() {
		foreach (__ARGS__[0], mapping f)
			update_one(f->uploader + "#" + f->channel, f->id);
	};
}

protected void create(string name) {
	::create(name);
	cleanup();
}
