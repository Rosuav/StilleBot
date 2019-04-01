inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	int delay = (int)req->variables->delay;
	if (delay)
	{
		object ret = Concurrent.Promise();
		call_out(lambda() {ret->success((["data": "Hello, world after " + delay + " seconds!",
			"type": "text/plain; charset=\"UTF-8\""]));}, delay);
		return ret->future();
	}
	return (["data": "Hello, world!", "type": "text/plain; charset=\"UTF-8\""]);
}

void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
