inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string msg = "Hello, world!";
	object ret = Concurrent.resolve(0);
	int delay = (int)req->variables->delay;
	if (delay) {
		msg += " We've delayed " + delay + " seconds!";
		ret = ret->delay(delay);
	}
	int sleep = (int)req->variables->sleep;
	if (sleep) {
		msg += " We've slept " + sleep + " milliseconds!";
		ret = ret->delay(sleep / 1000.0);
	}
	return ret->then(lambda() {return (["data": msg, "type": "text/plain; charset=\"UTF-8\""]);});
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
