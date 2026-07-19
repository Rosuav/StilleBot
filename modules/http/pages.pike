//Manage a GitHub Pages site
//Possibly will be able to push to other forms of hosting, for those for whom
//GH Pages is ill-suited.
inherit http_websocket;

//TODO: Add a secret so that we get X-Hub-Signature-256 headers

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"x-hub-signature-256", "content-type">);
		werror("Forwarding webhook...\n");
		Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
			Protocols.HTTP.Promise.Arguments((["headers": req->request_headers & headers, "data": req->body_raw])));
		//As in chan_integrations, not currently awaiting the promise. Should we?
		return "Passing it along.";
	}
	if (string sig = req->request_type == "POST" && req->request_headers["x-hub-signature-256"]) {
		string hmac_key = G->G->instance_config->github_hmac || "It's a Secret to Everybody"; //Test key as per https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
		object signer = Crypto.SHA256.HMAC(hmac_key);
		if (sig != "sha256=" + String.string2hex(signer(req->body_raw))) {
			werror("GitHub webhook - Failed HMAC check\n");
			return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
		}
		mapping data = Standards.JSON.decode_utf8(req->body_raw);
		if (!mappingp(data)) return (["error": 400, "data": "No data in body"]);
		werror("DATA %O\n", data);
	}
	return "Okay";
}

//TODO: Use the "push" webhook to be notified of changes, which we can then push out on the websocket
