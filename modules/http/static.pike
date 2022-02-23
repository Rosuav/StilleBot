inherit http_endpoint;

//Get the newest modified timestamp for a file or any of its deps
int _get_mtime(string filename, multiset|void ignore) {
	object stat = file_stat("httpstatic/" + filename);
	if (!stat) return 0;
	multiset deps = G->G->httpstatic_deps[filename];
	if (!deps) return stat->mtime;
	if (!ignore) ignore = (<filename>);
	int mtime = stat->mtime;
	foreach (deps; string dep;) if (!ignore[dep]) {
		ignore[dep] = 1;
		mtime = max(mtime, _get_mtime(dep));
	}
	return mtime;
}

constant http_path_pattern = "/static/%[^/]";
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string filename)
{
	if (filename == "" || has_prefix(filename, ".")) return (["error": 403, "data": "Forbidden"]);
	string dir = "httpstatic";
	//Support a small number of subdirectory names
	if (sscanf(filename, "upload-%s", filename) && filename && filename != "" && !has_prefix(filename, "."))
		dir = "httpstatic/uploads";
	//For absolute paranoia-level safety, instead of trying to open the
	//file directly, we check that the name comes up in a directory listing.
	if (!has_value(get_dir(dir), filename)) return (["error": 404, "data": "Not found"]);
	//TODO: Play nicely with caches by providing an etag, don't rely on modified timestamps
	object modsince = Calendar.ISO.parse("%e, %a %M %Y %h:%m:%s %z", req->request_headers["if-modified-since"] || "");
	if (modsince && _get_mtime(filename) <= modsince->unix_time()) return (["error": 304, "data": ""]);
	if (dir == "httpstatic" && has_suffix(filename, ".js")) {
		//See if the file has any import markers.
		string data = Stdio.read_file("httpstatic/" + filename);
		multiset deps = (<>);
		while (sscanf(data, "%s$$static||%[a-zA-Z_.]$$%s", string before, string fn, string after) == 3) {
			deps[fn] = 1;
			if (multiset grandchildren = G->G->httpstatic_deps[fn]) deps |= grandchildren;
			data = before + staticfile(fn) + after;
		}
		G->G->httpstatic_deps[filename] = deps;
		return ([
			"data": data,
			"type": "text/javascript",
		]);
	}
	return ([
		"file": Stdio.File(dir + "/" + filename),
		"extra_heads": (["Access-Control-Allow-Origin": "*"]),
	]);
}

//Handle /favicon.ico as if it were /static/favicon.ico
mapping(string:mixed) favicon(Protocols.HTTP.Server.Request req) {return http_request(req, "favicon.ico");}

string staticfile(string fn)
{
	//Not perfect but a lot better than nothing: add a cache-break marker
	//that changes when the file's mtime changes.
	int mtime = _get_mtime(fn);
	if (mtime) return sprintf("/static/%s?mtime=%d", fn, mtime);
	return "/static/" + fn;
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["favicon.ico"] = favicon;
	G->G->template_defaults["static"] = staticfile;
	if (!G->G->httpstatic_deps) G->G->httpstatic_deps = ([]);
}
