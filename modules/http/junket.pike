inherit http_endpoint;

void got_followers(string chan, array data)
{
	foreach (data, mapping follower)
	{
		write("New follower on %s: %s\n", chan, follower->from_name);
		echoable_message response = G->G->echocommands["!follower#" + chan];
		if (!response) continue;
		if (object chan = G->G->irc->channels["#" + chan])
			chan->wrap_message(([
				"user": follower->from_name,
				"displayname": follower->from_name,
			]), response);
	}
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string c = req->variables["hub.challenge"]) //Hook confirmation from Twitch
		return (["data": c]);
	//write("Got junket: %O\n", req->variables);
	if (req->body_raw != "" && has_prefix(req->request_headers["content-type"], "application/json"))
	{
		object signer = G->G->webhook_signer[req->variables->follow || req->variables->status];
		//It's probably safe to assume that any message sent by Twitch is in UTF-8.
		//So we verify the signature, and then trust the rest. Also, we assume that
		//Twitch is using a sha256 HMAC; if they ever change that (eg sha512 etc),
		//the signatures will just start failing.
		if (!signer || req->request_headers["x-hub-signature"] != "sha256=" + String.string2hex(signer(req->body_raw)))
		{
			werror("Signature failed! Message discarded. Body:\n%O\nSig: %O\n",
				req->body_raw, req->request_headers["x-hub-signature"]);
			return (["data": "Signature mismatch"]); //HTTP 200 because it might just mean we did a code reload
		}
		mixed body = Standards.JSON.decode_utf8(req->body_raw);
		array|mapping data = mappingp(body) && body->data;
		if (!data) return (["error": 400, "data": "Unrecognized body type"]);
		if (req->variables->follow) got_followers(req->variables->follow, data);
		if (req->variables->status) //stream_status(req->variables->status, data);
			write("GOT STATUS UPDATE %O %O\n", req->variables->status, data);
		//werror("Data: %O\n", data);
		return (["data": "PRAD"]);
	}
}
