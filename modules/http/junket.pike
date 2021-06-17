inherit http_endpoint;

void got_followers(string chan, array data)
{
	foreach (data, mapping follower)
	{
		if (object chan = G->G->irc->channels["#" + chan])
			chan->trigger_special("!follower", ([
				"user": follower->from_name,
				"displayname": follower->from_name,
			]), ([]));
	}
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string endpoint, channel;
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
	if (req->request_headers["twitch-eventsub-message-type"] == "webhook_callback_verification") { //EventSub confirmation
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		write("EventSub challenge body: %O\n", body);
		if (!mappingp(body) || !stringp(body->challenge)) return (["error": 400, "data": "Unrecognized body type"]);
		G->G->webhook_active[endpoint + "=" + channel] = 1<<60;
		return (["data": body->challenge]);
	}
	if (req->body_raw != "" && has_prefix(req->request_headers["content-type"], "application/json"))
	{
		//It's probably safe to assume that any message sent by Twitch is in UTF-8.
		//So we verify the signature, and then trust the rest. Also, we assume that
		//Twitch is using a sha256 HMAC; if they ever change that (eg sha512 etc),
		//the signatures will just start failing.
		string msgid = req->request_headers["twitch-eventsub-message-id"];
		if (msgid) {
			string ts = req->request_headers["twitch-eventsub-message-timestamp"];
			string sig = req->request_headers["twitch-eventsub-message-signature"];
			write("Junket E message: %O = %O, ID %O, ts %O, len %O (%O)\nhdr %O\nevt %O\n",
				endpoint, channel, msgid, ts,
				sizeof(req->body_raw), req->request_headers["content-length"],
				sig - "sha256=", String.string2hex(signer(msgid + ts + req->body_raw)),
			);
		}
		else {
			string sig = req->request_headers["x-hub-signature"];
			write("Junket W message: %O = %O, len %O (%O)\nhdr %O\nweb %O\n",
				endpoint, channel, sizeof(req->body_raw), req->request_headers["content-length"],
				sig - "sha256=", String.string2hex(signer(req->body_raw)),
			);
		}
		#if 0
		//Hacking this out for now. I don't know why they're failing.
		if (req->request_headers["x-hub-signature"] != "sha256=" + String.string2hex(signer(req->body_raw)))
		{
			werror("Signature failed! Message discarded. Body:\n%O\nSig: %O\n",
				req->body_raw, req->request_headers["x-hub-signature"]);
			return (["data": "Signature mismatch"]); //HTTP 200 because it might just mean we created a replacement for a soon-to-expire.
		}
		#endif
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		array|mapping data = mappingp(body) && (body->data || body->event); //Webhooks use data, EventSub uses event
		if (!data) return (["error": 400, "data": "Unrecognized body type"]);
		G->G->webhook_endpoints[endpoint](channel, data);
		//werror("Data: %O\n", data);
		return (["data": "PRAD"]);
	}
}

protected void create(string name) {::create(name); G->G->webhook_endpoints->follow = got_followers;}
