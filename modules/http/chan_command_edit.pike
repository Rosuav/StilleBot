inherit http_endpoint;

//Map a flag name to a set of valid values for it
//Blank or null is always allowed, and will result in no flag being set.
constant valid_flags = ([
	"mode": (<"random">),
	"dest": (<"/w $$", "/w %s", "/web %s">),
	"access": (<"mod">),
	"visibility": (<"hidden">),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return (["error": 401]);
	mixed body = Standards.JSON.decode(req->body_raw);
	if (!body || !mappingp(body) || !stringp(body->cmdname)) return (["error": 400]);
	string cmd = String.trim(lower_case(body->cmdname) - "!");
	if (cmd == "") return (["error": 400]);
	cmd += req->misc->channel->name;
	echoable_message resp = G->G->echocommands[cmd];
	if (mappingp(resp)) resp = resp->message; //Discard any previous flags
	mapping flags = ([]);
	foreach (valid_flags; string flag; multiset ok)
	{
		if (ok[body[flag]]) flags[flag] = body[flag];
		else if (body[flag] && body[flag] != "") return (["error": 400]); //TODO: Be nicer in the message
	}
	if (sizeof(flags)) make_echocommand(cmd, flags | (["message": resp]));
	else make_echocommand(cmd, resp);
	return (["error": 204]);
}
