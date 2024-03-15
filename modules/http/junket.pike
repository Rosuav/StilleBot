inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string endpoint, arg;
	object handler;
	foreach (G->G->eventhook_types; endpoint; handler)
		if (arg = req->variables[endpoint]) break;
	if (req->request_headers["twitch-eventsub-message-type"] == "webhook_callback_verification") {
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		if (!mappingp(body) || !stringp(body->challenge)) return (["error": 400, "data": "Unrecognized body type"]);
		handler->have_subs[arg] = 1;
		return (["data": body->challenge]);
	}
	//HACK FOR TESTING: If the magic cookie is in the request, ignore HMAC and
	//body, and permit even a GET request to trigger something.
	if (G->G->eventhook_hack_cookie && req->variables->cookie == G->G->eventhook_hack_cookie) {
		werror("Event hook hack sent, simulating %O message for %O\n", endpoint, arg);
		handler->callback(arg, (["title": req->variables->title || "No Title", "choices": ({ }), "channel_points_voting": ([])]));
		return (["data": "Hack sent.\n"]);
	}
	if (req->body_raw == "" || !has_prefix(req->request_headers["content-type"], "application/json")) return 0;
	//It's probably safe to assume that any message sent by Twitch is in UTF-8.
	//So we verify the signature, and then trust the rest. Also, we assume that
	//Twitch is using a sha256 HMAC; if they ever change that (eg sha512 etc),
	//the signatures will just start failing.
	string msgid = req->request_headers["twitch-eventsub-message-id"];
	string ts = req->request_headers["twitch-eventsub-message-timestamp"];
	string sig = req->request_headers["twitch-eventsub-message-signature"];
	if (sig != "sha256=" + String.string2hex(handler->signer(msgid + ts + req->body_raw)))
		return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
	mixed body = Standards.JSON.decode_utf8(req->body_raw);
	array|mapping data = mappingp(body) && body->event;
	if (!data) return (["error": 400, "data": "Unrecognized body type"]);
	handler->callback(arg, data);
	return (["data": "PRAD"]);
}

//For junket hack testing, set a cookie and then remove this line again.
//protected void create(string name) {::create(name); G->G->eventhook_hack_cookie = "...";}
