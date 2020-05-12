inherit http_endpoint;

//constant scopes = "chat:read chat:edit whispers:read whispers:edit user_subscriptions"; //For authenticating the bot itself
//constant scopes = ""; //no scopes currently needed

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Attempt to sanitize or whitelist-check the destination. The goal is to permit
	//anything that could ever have been req->not_query for any legitimate request,
	//and to deny anything else. Much of this is replicating the routing done by
	//connection.pike's http_handler.
	string next = req->variables->next;
	if (!next) ; //No destination? No problem (will use magic at arrival time).
	else if (!has_prefix(req->not_query, "/")) next = 0; //Destination MUST be absolute within the server but with no protocol or host.
	else if (has_prefix(req->not_query, "/chan_")) next = 0; //These can't be valid (although they wouldn't hurt, they'd just 404).
	else if (G->G->http_endpoints[next[1..]]) ; //Destination is a simple target, clearly whitelisted
	else
	{
		function handler;
		foreach (G->G->http_endpoints; string pat; function h)
		{
			//Match against an sscanf pattern, and require that the entire
			//string be consumed. If there's any left (the last piece is
			//non-empty), it's not a match - look for a deeper pattern.
			array pieces = array_sscanf(req->not_query, pat + "%s");
			if (!pieces || !sizeof(pieces) || pieces[-1] != "") continue;
			handler = h;
			break;
		}
		if (!handler) next = 0;
		//Note that this will permit a lot of things that aren't actually valid, like /channels/SPAM/HAM
		//I'm not sure if I should be stricter here or if that's okay. You won't be
		//able to redirect outside of the StilleBot environment this way.
	}
	return twitchlogin(req, (<>), next);
}
