//Uploads include both art shares and alertbox GIFs/sounds
//NOTE: This *must* be able to function on a non-active bot. Uploads can be sent
//to any instance, and will not be redirected to main. This can result in logs
//on either Gideon or Sikorsky in the event of an upload failure.
inherit http_websocket;
constant subscription_valid = 1;

//Map the FFProbe results to their MIME types.
//If not listed, the file is unrecognized and will be rejected.
constant file_mime_types = ([
	//"apng": "image/apng"? "video/apng"? WHAT?!?
	"gif": "image/gif", "gif_pipe": "image/gif",
	"jpeg_pipe": "image/jpeg",
	"png_pipe": "image/png",
	"svg_pipe": "image/svg+xml",
	"matroska,webm": "video/webm",
	"mov,mp4,m4a,3gp,3g2,mj2": "video/mp4",
	"mp3": "audio/mp3",
	"wav": "audio/wav",
]);


constant http_path_pattern = "/upload/%[^/]";
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string fileid) {
	if (fileid == "") return (["error": 403, "data": "Forbidden"]);
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (mapping resp = ensure_login(req)) return resp; //Shouldn't happen, so this could just be an error if it's easier
		mapping file = await(G->G->DB->get_file(fileid));
		if (!file) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		if (file->metadata->url) return jsonify((["error": "File has already been uploaded"]));
		if (sizeof(req->body_raw) > file->metadata->size) return jsonify((["error": "Requested upload of " + file->size + " bytes, not " + sizeof(req->body_raw) + " bytes!"]));
		string mimetype;
		mapping rc = Process.run(({"ffprobe", "-", "-print_format", "json", "-show_format", "-v", "quiet"}), (["stdin": req->body_raw]));
		mixed raw_ffprobe = rc->stdout + "\n" + rc->stderr + "\n";
		if (!rc->exitcode) {
			catch {raw_ffprobe = Standards.JSON.decode(rc->stdout);};
			if (mappingp(raw_ffprobe)) mimetype = file_mime_types[raw_ffprobe->format->format_name];
		}
		if (!mimetype && (has_prefix(req->body_raw, "GIF87a") || has_prefix(req->body_raw, "GIF89a")))
			mimetype = "image/gif"; //For some reason FFMPEG doesn't always recognize GIFs.
		if (!mimetype && !file->metadata->mimetype) { //TODO: What if we get both, but they're different?
			Stdio.append_file("upload.log", sprintf(#"Unable to ffprobe file upl-%s
Channel: %d
File size: %d
Beginning of file: %O
FFProbe result: %O
Upload time: %s
-------------------------
", file->id, file->channel, sizeof(req->body_raw), req->body_raw[..64], raw_ffprobe, ctime(time())[..<1]));
			return jsonify((["error": "File type unrecognized. If it should have been supported, contact Rosuav and quote ID upl-" + file->id]));
		}
		file->metadata->url = sprintf("%s/upload/%s", G->G->instance_config->http_address, file->id);
		if (mimetype) file->metadata->mimetype = mimetype;
		string data = req->body_raw;
		//Hack: Autocrop if it was marked for so doing
		if (int ac = m_delete(file->metadata, "autocrop")) catch {
			mapping img = Image.ANY._decode(data);
			array bounds;
			if (ac == 2) {
				//Autocrop to convex hull
				array hull = find_convex_hull(img);
				if (hull) {
					//Find the extents of the hull. These will become our crop border.
					bounds = hull[0] * 2;
					foreach (hull, [int x, int y]) {
						if (x < bounds[0]) bounds[0] = x;
						if (y < bounds[1]) bounds[1] = y;
						if (x > bounds[2]) bounds[2] = x;
						if (y > bounds[3]) bounds[3] = y;
					}
				}
			} else {
				//Check the four corners. If the image is completely transparent in all four,
				//autocrop away all transparency. TODO: If the image is transparent in any two
				//adjacent corners, autocrop that edge, and if it is in three corners, autocrop
				//both contained edges.
				if (img->alpha && !sizeof((
					img->alpha->getpixel(0, 0) +
					img->alpha->getpixel(0, img->ysize - 1) +
					img->alpha->getpixel(img->xsize - 1, 0) +
					img->alpha->getpixel(img->xsize - 1, img->ysize - 1)
				) - ({0}))) {
					bounds = img->alpha->find_autocrop();
				}
			}
			//Should we always reencode back to the original format? For now just using WebP and PNG.
			if (img->format == "image/webp")
				data = Image.WebP.encode(img->image->copy(@bounds), (["alpha": img->alpha->copy(@bounds)]));
			else {
				data = Image.PNG.encode(img->image->copy(@bounds), (["alpha": img->alpha->copy(@bounds)]));
				file->metadata->mimetype = "image/png";
			}
			//TODO: Adjust the size and allocation
		};
		file->metadata->etag = String.string2hex(Crypto.SHA1.hash(data));
		await(G->G->DB->update_file(file->id, file->metadata, data));
		return jsonify((["url": file->url]));
	}
	array(string) parts = fileid / "-";
	if (sizeof(parts) != 5) { //Not a UUID. Probably a legacy URL.
		string|zero redir = await(G->G->DB->load_config(0, "upload_redirect"))[parts[-1]];
		return redir && redirect(redir, 301); //If we don't have a redirect, it's probably deleted, so... 404.
	}
	//The file might not be uploaded yet. Try a few times to see if we get it.
	mapping file;
	for (int tries = 0; tries < 10; ++tries) {
		file = await(G->G->DB->get_file(fileid, 1));
		if (!file) return 0;
		if (file->data != "") break;
		sleep(1);
	}
	if (req->request_headers["if-none-match"] == file->metadata->etag) return (["error": 304]);
	return ([
		"data": file->data,
		"type": file->metadata->mimetype,
		"extra_heads": (["ETag": "\"" + file->metadata->etag + "\""]),
	]);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//This socket never needs to be connected to, nor subscribed to; it exists so that
	//you can send secondary commands to any socket and have them appear here.
	return "Subcommands only";
}

__async__ mapping|zero wscmd_upload_file(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->type, "chan_%s", string owner);
	if (!owner) return (["cmd": "upload_error", "error": "Uploading without a channel"]); //Shouldn't happen unless user is fiddling around
	object core_handler = G->G->websocket_types[conn->type];
	string|mapping prep = await(core_handler->file_upload_prepare(channel, conn, msg));
	if (stringp(prep)) return (["cmd": "upload_error", "name": msg->name, "error": prep]);
	if (!mappingp(prep)) return (["cmd": "upload_error", "name": msg->name, "error": "Internal error"]); //Buggy module
	int ephemeral = m_delete(prep, "_ephemeral");
	//Special case: Ephemeral files, and ONLY ephemeral files, may be uploaded by non-mods.
	if (!ephemeral && !conn->is_mod) return (["cmd": "upload_error", "name": msg->name, "error": "File uploading is restricted to moderators."]);
	prep->owner = owner;
	mapping file = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, prep, ephemeral));
	if (file->error) return (["cmd": "upload_error", "name": msg->name, "error": file->error]);
	core_handler->file_upload_started(channel, conn, msg, file);
	return (["cmd": "upload", "name": msg->name, "id": file->id]);
}

//TODO: Have a thing on code reload or somewhere that cleans out upload_redirect,
//removing entries for files that are no longer present. That way, if those files
//eventually get deleted, we'll throw away their metadata.
