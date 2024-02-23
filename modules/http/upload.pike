//Uploads include both art shares and alertbox GIFs/sounds
inherit http_endpoint;

constant MAX_PER_FILE = 16;
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


constant http_path_pattern = "/upload/%[^/]";
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string fileid) {
	if (fileid == "") return (["error": 403, "data": "Forbidden"]);
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (mapping resp = ensure_login(req)) return resp; //Shouldn't happen, so this could just be an error if it's easier
		mapping file = await(G->G->DB->get_file(fileid));
		if (!file) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		if (file->metadata->url) return jsonify((["error": "File has already been uploaded"]));
		if (sizeof(req->body_raw) > MAX_PER_FILE * 1048576) return jsonify((["error": "Upload exceeds maximum file size"]));
		string mimetype;
		mapping rc = Process.run(({"ffprobe", "-", "-print_format", "json", "-show_format", "-v", "quiet"}), (["stdin": req->body_raw]));
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
			return jsonify((["error": "File type unrecognized. If it should have been supported, contact Rosuav and quote ID art-" + file->id]));
		}
		file->metadata->url = sprintf("%s/upload/%s", persist_config["ircsettings"]->http_address, file->id);
		file->metadata->mimetype = mimetype; //TODO: What if we got one from the client? Should we report discrepancies?
		file->metadata->etag = String.string2hex(Crypto.SHA1.hash(req->body_raw));
		G->G->DB->upload_file(file->id, req->body_raw, file->metadata);
		function cb = G->G->websocket_types[file->expires ? "chan_share" : "chan_alertbox"]->file_uploaded;
		if (cb) cb(file->channel, req->misc->session->user, file);
		return jsonify((["url": file->url]));
	}
	mapping file = await(G->G->DB->get_file(fileid, 1));
	if (!file) return 0;
	if (req->request_headers["if-none-match"] == file->metadata->etag) return (["error": 304]);
	return ([
		"data": file->data,
		"type": file->metadata->mimetype,
		"extra_heads": (["ETag": "\"" + file->metadata->etag + "\""]),
	]);
}

