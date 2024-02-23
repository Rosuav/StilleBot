//Uploads include both art shares and alertbox GIFs/sounds
inherit http_endpoint;

constant http_path_pattern = "/upload/%[^/]";
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string fileid) {
	if (fileid == "") return (["error": 403, "data": "Forbidden"]);
	werror("REQUEST: %O\n", fileid);
	mapping file = await(G->G->DB->get_file(fileid, 1));
	if (!file) return 0;
	if (req->request_headers["if-none-match"] == file->metadata->etag) return (["error": 304]);
	return ([
		"data": file->data,
		"type": file->metadata->mimetype,
		"extra_heads": (["ETag": "\"" + file->metadata->etag + "\""]),
	]);
}

