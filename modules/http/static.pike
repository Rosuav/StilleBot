inherit http_endpoint;

constant http_path_pattern = "/static/%[^/]";
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//TODO: Handle static files eg CSS
	//The pattern's sscanf result will be made available in req->misc somewhere.
}
