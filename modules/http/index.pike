inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return (["data": "Hello, world!", "type": "text/plain; charset=\"UTF-8\""]);
}

void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
