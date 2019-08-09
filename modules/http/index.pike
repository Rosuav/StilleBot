inherit http_endpoint;

//TODO: Replace this with the built-in now that one exists.
class Waiter
{
	inherit Concurrent.Promise;
	protected void create(int|float delay)
	{
		::create();
		call_out(success, delay);
	}
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string msg = "Hello, world!";
	object ret = Concurrent.resolve(0);
	int delay = (int)req->variables->delay;
	if (delay) ret = ret->then(lambda() {
		msg += " We've delayed " + delay + " seconds!";
		return Waiter(delay);
	});
	int sleep = (int)req->variables->sleep;
	if (sleep) ret = ret->then(lambda() {
		msg += " We've slept " + sleep + " milliseconds!";
		return Waiter(sleep / 1000.0);
	});
	return ret->then(lambda() {return (["data": msg, "type": "text/plain; charset=\"UTF-8\""]);});
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
