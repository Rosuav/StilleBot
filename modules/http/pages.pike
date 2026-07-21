//Manage a GitHub Pages site
//Possibly will be able to push to other forms of hosting, for those for whom
//GH Pages is ill-suited.
inherit http_websocket;

//Cache the generated token until it's close to expiring
//Not retained across code reloads as it'll never have more than ten minutes of validity anyway
string|zero jwt; int jwt_expiration;
string github_jwt() {
	if (jwt_expiration > time() + 60) return jwt;
	mapping claims = ([
		"exp": jwt_expiration = time() + 540, //GitHub demands no more than 10 minutes of validity; give 9 for safety.
		"iss": G->G->instance_config->github_clientid,
		"alg": "RS256",
	]);
	string pk = Standards.PEM.Messages(Stdio.read_file("github-key.pem"))->get_private_key();
	object sign = Standards.PKCS.RSA.parse_private_key(pk);
	//If the public key is needed, Standards.JSON.encode(sign->jwk()) will provide it in the right format.
	return jwt = Web.encode_jwt(sign, claims);
}

string|zero install_token; int install_token_expiration;
__async__ mapping|array github_api_request(string endpoint, mapping|void options) {
	if (!options) options = ([]);
	//In API requests, send headers:
	mapping headers = ([
		"Accept": "application/vnd.github+json",
		"X-GitHub-Api-Version": "2026-03-10",
		"User-Agent": "Mustard-Mine",
	]);
	switch (options->authtype || "token") {
		case "JWT": headers->Authorization = "Bearer " + github_jwt(); break;
		case "token": {
			//First get an access token for the installation. These expire in an hour.
			if (install_token_expiration < time() + 60) {
				//FIXME: How are we supposed to know the correct installation ID? Should that go into instance_config?
				mapping token = await(github_api_request("/app/installations/147687849/access_tokens", (["method": "POST", "authtype": "JWT"])));
				if (!token->token) return (["error": "Unable to get token", "raw": token]);
				install_token_expiration = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", token->expires_at)->unix_time();
				install_token = token->token;
			}
			headers->Authorization = "Bearer " + install_token;
			break;
		}
		default: break; //Unauthenticated
	}
	string body = options->data;
	if (options->json) {
		headers["Content-Type"] = "application/json";
		body = Standards.JSON.encode(options->json, 1);
	}
	string method = options->method || (body ? "POST" : "GET");
	Protocols.HTTP.Promise.Result res = await(Protocols.HTTP.Promise.do_method(method, "https://api.github.com" + endpoint,
			Protocols.HTTP.Promise.Arguments((["headers": headers, "data": body]))));
	if (res->status == 204 && res->get() == "") return ([]);
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	//TODO: error handling
	return data;
}

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"x-hub-signature-256", "x-github-event", "x-github-delivery", "content-type">);
		//Possibly also of interest: x-github-hook-{id,installation-target-id,installation-target-type}
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
		werror("GITHUB HOOK %O %O\n", req->request_headers["x-github-event"], data);
		return "Okay";
	}
	/* Create:
	mixed repos = await(github_api_request("/orgs/mustardmine/repos", (["json": ([
		"name": "Template",
		"description": "Template for new repositories",
		"visibility": "public",
	])])));
	// */
	/* Create from template:
	mixed repos = await(github_api_request("/repos/mustardmine/template/generate", (["json": ([
		"owner": "mustardmine",
		"name": "Example",
		"description": "Example newly-made site",
	])])));
	// */
	//Delete:
	//mixed repos = await(github_api_request("/repos/mustardmine/TestRepo", (["method": "DELETE"])));
	/* Edit contents:
	mapping file = await(github_api_request("/repos/mustardmine/example/contents/index.md"));
	mapping repos = await(github_api_request("/repos/mustardmine/example/contents/index.md", (["method": "PUT", "json": ([
		"sha": file->sha,
		"message": "Update web site",
		"committer": (["name": "SomeUserName", "email": "142857@twitchuser.invalid"]),
		"content": MIME.encode_base64(#"# My new web site

Testing out some stuff with GH Pages and the GH API.
", 1),
	])])));
	if (repos->status == "409") ; //File was edited while you were looking at it
	repos->hack_previous_content = MIME.decode_base64(file->content);
	// */
	//List:
	mixed repos = await(github_api_request("/orgs/mustardmine/repos"));
	return sprintf("Repositories: %O\n", repos);
}

//TODO: Use the "push" webhook to be notified of changes, which we can then push out on the websocket
