inherit http_websocket;
constant markdown = #"# Alertbox management for channel $$channel$$

<div id=uploadfrm><div id=uploads></div></div>

<form>Upload new file: <input type=file multiple></form>

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
#uploads > figure {
	border: 1px solid black; /* TODO: Show incomplete uploads with a different border */
	margin: 0.5em;
	padding: 0.5em;
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
figcaption {max-width: 150px;}
.thumbnail audio {max-width: 100%; max-height: 100%;}
</style>
";

constant MAX_PER_FILE = 5, MAX_TOTAL_STORAGE = 25; //MB

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//TODO: Give some useful info if not a mod, since that might be seen if someone messes up the URL
	if (!req->misc->is_mod) return render(req, req->misc->chaninfo);
	if (req->request_type == "POST") {
		mapping cfg = persist_status->path("alertbox", (string)req->misc->channel->userid);
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
		send_updates_all("control" + req->misc->channel->name); //Display connection doesn't need to get updated.
		return jsonify((["url": file->url]));
	}
	//TODO: If key=X set and correct, use group "display"
	//TODO: If key=X set but incorrect, give static error
	return render(req, ([
		"vars": (["ws_group": "control", "maxfilesize": MAX_PER_FILE, "maxtotsize": MAX_TOTAL_STORAGE]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	array files = ({ });
	//TODO: Enumerate files in upload order (or upload authorization order)
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (id) {
		if (!cfg->files) return 0;
		int idx = search(cfg->files->id, id);
		return idx >= 0 && cfg->files[idx];
	}
	return (["items": cfg->files || ({ }),
		//TODO: All details about text positioning and style
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
	send_updates_all(conn->group); //Note that the display connection doesn't need to be updated
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
	write("%O\n", file);
	string fn = sprintf("%d-%s", channel->userid, file->id);
	rm("httpstatic/uploads/" + fn); //If it returns 0 (file not found/not deleted), no problem
	m_delete(persist_status->path("upload_metadata"), fn);
	persist_status->save();
	//TODO: See if the file was being used by an alert, and if so, remove it and
	//update the display group.
	update_one(conn->group, file->id);
}

void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (grp != "control") return;
	//TODO: Send a test alert. This message comes in on the control connection,
	//and signals everything in the display group.
}
