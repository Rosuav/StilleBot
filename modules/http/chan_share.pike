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
<div class=uploadtarget></div>

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

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (mapping resp = ensure_login(req)) return resp;
	return render(req, ([
		"vars": (["ws_group": (string)req->misc->session->user->id,
			//Not currently shown anywhere; if you exceed the limit, you'll be told.
			//"maxfilesize": G->G->DB->MAX_PER_FILE, "maxfiles": G->G->DB->MAX_EPHEMERAL_FILES,
			"user_types": user_types, "is_mod": req->misc->is_mod,
		]),
	]) | req->misc->chaninfo);
}

@hook_ephemeral_file_edited: __async__ void file_uploaded(mapping file) {
	mapping user = await(get_user_info(file->uploader, "id"));
	update_one(user->id + "#" + file->channel, file->id);
	mapping settings = await(G->G->DB->load_config(file->channel, "artshare"));
	G->G->irc->id[file->channel]->send(
		(["displayname": user->display_name]),
		settings->msgformat || DEFAULT_MSG_FORMAT,
		(["{URL}": file->metadata->url, "{sharerid}": user->id, "{fileid}": file->id]),
	) {[mapping vars, mapping params] = __ARGS__;
		//Note that the channel ID isn't strictly necessary, as any deletion signal will
		//itself be associated with that channel; but it's nice to have for debugging.
		artshare_messageid[params->id] = ({(string)file->channel, vars["{sharerid}"], vars["{fileid}"]});
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

__async__ void delete_file(object channel, string userid, string fileid) {
	array files = await(G->G->DB->purge_ephemeral_files(channel->userid, userid, fileid));
	if (sizeof(files)) {
		update_one(userid + "#" + channel->userid, fileid);
		if (string id = artshare_file_messageid[fileid]) channel->send(([]), "/deletemsg " + id);
	}
}

mapping|zero websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return 0;
	delete_file(channel, grp, msg->id);
}

@"is_mod": __async__ void wscmd_config(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
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
