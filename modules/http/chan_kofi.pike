inherit http_endpoint;
//This functionality has been renamed to Integrations to allow others to be added too.
//However, Ko-fi doesn't seem to process redirects, so we sneakily pass the request over
//to the /integrations handler.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (req->request_type == "POST" && req->variables->data)
		return G->G->http_endpoints->chan_integrations(req);
	return redirect("integrations", 308);
}
