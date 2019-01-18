inherit http_endpoint;

constant http_path_pattern = "/static/%[^/]";
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, string filename)
{
	//TODO: Handle static files eg CSS
	write("Static file: %O\n", filename);
	return (["data": "fn: " + filename]);
}
