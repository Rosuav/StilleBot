inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	return render_template("index.md", ([]));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
