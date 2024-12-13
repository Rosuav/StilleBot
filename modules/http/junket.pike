inherit http_endpoint;

__async__ void confirm_conduit_active() {
	//Wait a bit, then see if the conduit's active. If it isn't, scream.
	//If that doesn't work? Maybe we need to activate ourselves.
	mapping resp = await(twitch_api_request("https://api.twitch.tv/helix/eventsub/conduits/shards?conduit_id=" + G->G->condid));
	werror("Pre-check, conduit status %O\n", resp->data);
	sleep(5);
	resp = await(twitch_api_request("https://api.twitch.tv/helix/eventsub/conduits/shards?conduit_id=" + G->G->condid));
	werror("Post-check, conduit status %O\n", resp->data);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//Hack: Using this for Google oauth for the timebeing
	if (req->variables->code && has_prefix(req->variables->scope || "??", "https://www.googleapis.com/auth/")) {
		mapping state = m_delete(G->G->google_logins_pending, req->variables->state);
		if (!state || state->time < time() - 86400) return redirect("/c/calendar");
		mapping cred = await(G->G->DB->load_config(0, "googlecredentials"));
		object res = await(Protocols.HTTP.Promise.post_url("https://oauth2.googleapis.com/token",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Content-Type": "application/json; charset=utf-8",
			]), "data": Standards.JSON.encode(([
				"client_id": cred->client_id,
				"client_secret": cred->client_secret,
				"code": req->variables->code,
				"grant_type": "authorization_code",
				"redirect_uri": state->redirect_uri,
			]))]))
		));
		werror("OAUTH HEADERS %O\n", res->headers);
		mapping oauth = Standards.JSON.decode_utf8(res->get());
		werror("OAUTH GET %O\n", oauth);
		G->G->DB->mutate_config(state->channel, "calendar") {
			__ARGS__[0]->oauth = oauth;
		};
		//Redirecting back to the calendar page probably means people will have two tabs open.
		//Probably not worth the hassle though. They can always close this one anyway.
		return redirect("/c/calendar");
	}
	if (!req->variables->conduitbroken) return 0; //The only webhook handler now is this one.
	if (req->request_headers["twitch-eventsub-message-type"] == "webhook_callback_verification") {
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		if (!mappingp(body) || !stringp(body->challenge)) return (["error": 400, "data": "Unrecognized body type"]);
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
	mapping secrets = await(G->G->DB->load_config(0, "eventhook_secret"));
	string secret = secrets[G->G->instance_config->local_address];
	object signer = Crypto.SHA256.HMAC(secret);
	if (sig != "sha256=" + String.string2hex(signer(msgid + ts + req->body_raw)))
		return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
	mixed body = Standards.JSON.decode_utf8(req->body_raw);
	array|mapping data = mappingp(body) && body->event;
	if (!data) return (["error": 400, "data": "Unrecognized body type"]);
	werror("Conduit broken! %O\n", data); //Probably a non-event if we're active??
	if (is_active_bot()) G->G->setup_conduit();
	else if (string other = get_active_bot()) {
		//Forward the request to the other bot.
		//Note that the notification itself gives no feedback. So we wait a few seconds,
		//then check to see if the conduit is now active.
		G->G->DB->query_rw(sprintf("notify \"stillebot.conduit_broken\", '%s for %s'", G->G->instance_config->local_address || "unknown", other));
		confirm_conduit_active();
	}
	else if (G->G->emergency) G->G->emergency();
	else werror("CONDUIT LOST ON INACTIVE BOT, NO RECOURSE\n"); //Should only happen in a crisis situation eg main bot down, standby not yet promoted
	return (["data": "PRAD"]);
}
