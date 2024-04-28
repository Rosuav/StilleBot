inherit http_endpoint;

string http_request(Protocols.HTTP.Server.Request req) {return req->get_ip();}
