inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	werror("Got VLC notification: %O\n", req->variables);
	return (["data": "Okay, fine\n", "type": "text/plain"]);
}
