inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string endpoint, arg;
	object handler;
	foreach (G->G->eventhook_types; endpoint; handler)
		if (arg = req->variables[endpoint]) break;
	if (!arg) {
		//Try to find a legacy webhook
		string channel;
		foreach (G->G->webhook_endpoints; endpoint; )
			if (channel = req->variables[endpoint]) break;
		object signer = G->G->webhook_signer[endpoint + "=" + channel];
		if (!signer) return (["data": "Unknown junket response"]); //HTTP 200 because it might just mean we did a code reload
		if (string c = req->variables["hub.challenge"]) //Hook confirmation from Twitch
		{
			int duration = (int)req->variables["hub.lease_seconds"];
			if (G->G->webhook_active[endpoint + "=" + channel] < duration)
				//Record the time-to-live so we don't wait for the next ping
				//If it's wrong (eg it's a few seconds too generous due to lag),
				//poll.pike will correct it before long.
				G->G->webhook_active[endpoint + "=" + channel] = duration;
			return (["data": c]);
		}
		if (req->body_raw == "" || !has_prefix(req->request_headers["content-type"], "application/json")) return 0;
		string sig = req->request_headers["x-hub-signature"];
		if (sig != "sha256=" + String.string2hex(signer(req->body_raw)))
			return (["error": 418, "data": "That tea's cold by now."]); //Most likely we've changed the signer.
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		array|mapping data = mappingp(body) && body->data;
		if (!data) return (["error": 400, "data": "Unrecognized body type"]);
		G->G->webhook_endpoints[endpoint](channel, data);
		return (["data": "PRAD"]);
	} //End legacy handling.
	if (req->request_headers["twitch-eventsub-message-type"] == "webhook_callback_verification") {
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		if (!mappingp(body) || !stringp(body->challenge)) return (["error": 400, "data": "Unrecognized body type"]);
		handler->have_subs[arg] = 1;
		return (["data": body->challenge]);
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
