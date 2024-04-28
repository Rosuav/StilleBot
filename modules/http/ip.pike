inherit http_endpoint;

string http_request(Protocols.HTTP.Server.Request req) {
	mapping cfg = G->G->instance_config;
	if (string fwd = cfg->http_forwarded && req->request_headers["x-forwarded-for"]) return fwd;
	return req->get_ip();
}
