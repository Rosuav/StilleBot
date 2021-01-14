inherit http_endpoint;
//Stub. This functionality has been merged into variable handling.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return redirect("variables");
}
