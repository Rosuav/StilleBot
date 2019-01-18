inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->body_raw != "" && has_prefix(req->request_headers["content-type"], "application/json"))
	{
		object signer = G->G->webhook_signer[req->variables->follow];
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
		foreach (data, mapping follower)
		{
			write("New follower on %s: %s\n", req->variables->follow, follower->from_name);
			echoable_message response = G->G->echocommands["!follower#" + req->variables->follow];
			if (!response) continue;
			if (object chan = G->G->irc->channels["#" + req->variables->follow])
				chan->wrap_message(([
					"user": follower->from_name,
					"displayname": follower->from_name,
				]), response);
		}
		//werror("Data: %O\n", data);
		return (["data": "PRAD"]);
	}
}
