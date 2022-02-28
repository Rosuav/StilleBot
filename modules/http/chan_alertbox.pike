inherit http_websocket;
constant markdown = #"# Alertbox management for channel $$channel$$

> ### Library
>
> Upload files (up to 5MB each) to use in your alerts. You may also
> link to files that are accessible on the internet.
>
> <div id=uploadfrm><div id=uploads></div></div>
>
> <p><label class=selectmode><input type=radio name=chooseme data-special=None> None<br></label>
> <span class=selectmode><input type=radio name=chooseme data-special=URL><label> URL: <input id=customurl size=100></label><br></span>
> <form>Upload new file: <input type=file multiple></form></p>
>
> [Select](:#libraryselect disabled=true) [Close](:.dialog_close)
{: tag=dialog #library}

Drag this to OBS or use this URL as a browser source: <a id=alertboxlink href=\"alertbox?key=LOADING\">Alert Box</a><br>
Keep this link secret; if the authentication key is accidentally shared, you can [Revoke Key](:#revokekey) to generate a new one.

[Show library](:.showlibrary) [Send test alert](:.testalert)

> ### Revoke authentication key
>
> If your authentication key is accidentally shared, don't panic! It can be quickly and<br>
> easily revoked here, before anyone can use it to snoop on your alerts.
>
> After doing this, you will need to update any browser sources showing your alerts,<br>
> but all your configuration will be retained.
>
> [Generate a new key, disabling the old one](:#confirmrevokekey) [Cancel](:.dialog_close)
{: tag=dialog #revokekeydlg}

<div id=alertconfigs></div>

> ### Delete file
> Really delete this file?
>
> [...](...)
>
> <div class=thumbnail></div>
>
> Once deleted, this file will no longer be available for alerts, and if<br>
> reuploaded, will have a brand new URL.
>
> [Delete](:#delete) [Cancel](:.dialog_close)
{: tag=dialog #confirmdeletedlg}


<style>
#uploadfrm {
	border: 1px solid black;
	background: #eee;
	padding: 1em;
}
#uploads {
	display: flex;
	flex-wrap: wrap;
}
#uploads > label {
	border: 1px solid black; /* TODO: Show incomplete uploads with a different border */
	margin: 0.5em;
	padding: 0.5em;
	position: relative;
}
#uploads figure {
	margin: 0;
	padding: 0 1em;
}
#uploads input[type=radio] {
	position: absolute;
}
input[name=chooseme]:checked ~ figure {
	background: aliceblue;
}
#uploads .active {
	/* TODO: Style the library elements so you can see which ones are selectable.
	When you simply 'show library', that's all of them (but the radio buttons are
	disabled); but if you ask to select an image or sound, only those of that type
	are active (and will have radio buttons). */
}
#uploads .inactive {
	/* Alternatively, style the inactive ones. Current placeholder: crosshatched. */
	filter: grayscale(50%);
	background: repeating-linear-gradient(
		-45deg,
		#eee,
		#eee 10px,
		#ccc 10px,
		#ccc 12px
	);
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
.thumbnail audio {max-width: 100%; max-height: 100%;}

.alertconfig {
	margin: 3px;
	border: 1px solid black;
	padding: 8px;
}

#library.noselect .selectmode {display: none;}
.preview {
	max-height: 2em;
	vertical-align: middle;
}
input[type=range] {vertical-align: middle;}
</style>

> ### Alert preview
>
> Your alerts currently look like this:
>
> <iframe id=alertembed width=600 height=400></iframe>
>
> [Send test alert](:.testalert) [Close](:.dialog_close)
{: tag=dialog #previewdlg}
";

constant MAX_PER_FILE = 5, MAX_TOTAL_STORAGE = 25; //MB
constant ALERTTYPES = ([
	"hostalert": "When some other channel hosts yours",
	//Currently only the one, but leave open the possibility for more in the future
]);
constant RETAINED_ATTRS = ({"image", "sound"});
constant GLOBAL_ATTRS = "format alertlength alertgap" / " ";
constant FORMAT_ATTRS = ([
	"text_image_stacked": "layout alertwidth alertheight textformat volume" / " " + TEXTFORMATTING_ATTRS,
	"text_image_overlaid": "layout alertwidth alertheight textformat volume" / " " + TEXTFORMATTING_ATTRS,
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string key = req->variables->key) {
		//TODO: If key is incorrect, give static error, something readable.
		if (key != persist_status->path("alertbox", (string)req->misc->channel->userid)->authkey)
			return (["error": 401, "data": "Bad key", "type": "text/plain"]);
		return render_template("alertbox.html", ([
			"vars": (["ws_type": ws_type, "ws_code": "alertbox", "ws_group": req->variables->key + req->misc->channel->name]),
			"channelname": req->misc->channel->name[1..],
		]) | req->misc->chaninfo);
	}
	//TODO: Give some useful info if not a mod, since that might be seen if someone messes up the URL
	if (string scopes = req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "chat:read"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	if (!req->misc->is_mod) return render(req, req->misc->chaninfo);
	mapping cfg = persist_status->path("alertbox", (string)req->misc->channel->userid);
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (!req->variables->id) return jsonify((["error": "No file ID specified"]));
		int idx = search((cfg->files || ({ }))->id, req->variables->id);
		if (idx < 0) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		mapping file = cfg->files[idx];
		if (file->url) return jsonify((["error": "File has already been uploaded"]));
		if (file->size < sizeof(req->body_raw)) return jsonify((["error": "Requested upload of " + file->size + "bytes, not " + sizeof(req->body_raw) + " bytes!"]));
		string filename = sprintf("%d-%s", req->misc->channel->userid, file->id);
		Stdio.write_file("httpstatic/uploads/" + filename, req->body_raw);
		file->url = sprintf("%s/static/upload-%s", persist_config["ircsettings"]->http_address, filename);
		persist_status->path("upload_metadata")[filename] = (["mimetype": file->mimetype]);
		persist_status->save();
		update_one("control" + req->misc->channel->name, file->id); //Display connection doesn't need to get updated.
		return jsonify((["url": file->url]));
	}
	return render(req, ([
		"vars": (["ws_group": "control", "maxfilesize": MAX_PER_FILE, "maxtotsize": MAX_TOTAL_STORAGE]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (grp == cfg->authkey) {
		//Cut-down information for the display
		string chan = channel->name[1..];
		string token;
		if (channel->name == "#!demo") token = "!demo"; //Permit test alerts but no chat connection
		else if (has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:read"))
			token = persist_status->path("bcaster_token")[chan];
		return ([
			"alertconfigs": cfg->alertconfigs || ([]),
			"token": token,
		]);
	}
	if (grp != "control") return 0; //If it's not "control" and not the auth key, it's probably an expired auth key.
	array files = ({ });
	if (id) {
		if (!cfg->files) return 0;
		int idx = search(cfg->files->id, id);
		return idx >= 0 && cfg->files[idx];
	}
	if (!cfg->authkey) {cfg->authkey = String.string2hex(random_string(11)); persist_status->save();}
	return (["items": cfg->files || ({ }),
		"authkey": cfg->authkey,
		"alertconfigs": cfg->alertconfigs || ([]),
		"alerttypes": ALERTTYPES,
	]);
}

void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->files) cfg->files = ({ });
	if (!intp(msg->size) || msg->size < 0) return; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	int used = `+(0, @cfg->files->allocation);
	//Count 1KB chunks, rounding up, and adding one chunk for overhead. Won't make much
	//difference to most files, but will stop someone from uploading twenty-five million
	//one-byte files, which would be just stupid :)
	int allocation = (msg->size + 2047) / 1024;
	string error;
	if (!has_prefix(msg->mimetype, "image/") && !has_prefix(msg->mimetype, "audio/"))
		error = "Currently only audio and image files are supported - video support Coming Soon";
	else if (msg->size > MAX_PER_FILE * 1048576)
		error = "File too large (limit " + MAX_PER_FILE + " MB)";
	else if (used + allocation > MAX_TOTAL_STORAGE * 1024)
		error = "Unable to upload, storage limit of " + MAX_TOTAL_STORAGE + " MB exceeded. Delete other files to make room.";
	//TODO: Check if the file name is duplicated? Maybe? Not sure. It's not a fundamental blocker.
	//TODO: Sanitize the name - at least a length check.
	if (error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "uploaderror", "name": msg->name, "error": error]), 4));
		return;
	}
	string id;
	while (has_value(cfg->files->id, id = String.string2hex(random_string(14))))
		; //I would be highly surprised if this loops at all, let alone more than once
	cfg->files += ({([
		"id": id, "name": msg->name,
		"size": msg->size, "allocation": allocation,
		"mimetype": msg->mimetype, //TODO: Ensure that it's a valid type, or at least formatted correctly
	])});
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id); //Note that the display connection doesn't need to be updated
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
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

void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	//NOTE: Fake clients are fully allowed to send test alerts, but they will go
	//to *every* client. This means multiple people playing with the demo
	//simultaneously will see each other's alerts show up.
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	send_updates_all(cfg->authkey + channel->name, (["send_alert": channel->name[1..]])); //TODO: Use the display name
}

void websocket_cmd_alertcfg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!ALERTTYPES[msg->type]) return;
	if (!msg->format) {
		//If the format is not specified, this is a partial update, which can
		//change only the RETAINED_ATTRS - all others are left untouched.
		mapping data = cfg->alertconfigs[?msg->type]; if (!data) return;
		foreach (RETAINED_ATTRS, string attr) if (msg[attr]) data[attr] = msg[attr];
		persist_status->save();
		send_updates_all(conn->group);
		send_updates_all(cfg->authkey + channel->name);
		return;
	}
	array attrs = FORMAT_ATTRS[msg->format];
	if (!attrs) return;
	//If the format *is* specified, this is a full update, *except* for the retained
	//attributes. Other forms of partial update are not supported; instead, any
	//unspecified attribute will be deleted.
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	//TODO: Validate (see commands for example of deep validation)
	mapping data = cfg->alertconfigs[msg->type] =
		mkmapping(RETAINED_ATTRS, (cfg->alertconfigs[msg->type]||([]))[RETAINED_ATTRS[*]])
		| mkmapping(GLOBAL_ATTRS, msg[GLOBAL_ATTRS[*]])
		| mkmapping(attrs, msg[attrs[*]]);
	data->text_css = textformatting_css(data);
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
}

void websocket_cmd_rename(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//TODO: Rename a file. Won't change its URL (since that's based on ID),
	//nor the name of the file as stored (ditto), so this is really an
	//"edit description" endpoint. But users will think of it as "rename".
}

void websocket_cmd_revokekey(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	string prevkey = m_delete(cfg, "authkey");
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(prevkey + channel->name, (["breaknow": 1]));
}
