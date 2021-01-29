inherit http_endpoint;

//Map a flag name to a set of valid values for it
//Blank or null is always allowed, and will result in no flag being set.
constant valid_flags = ([
	"mode": (<"random">),
	"access": (<"mod">),
	"visibility": (<"hidden">),
	"action": (<"add">),
]);

constant condition_parts = ([
	"string": ({"expr1", "expr2"}),
	"number": ({"expr1"}), //Yes, expr1 even though there's no others - means you still see it when you switch (when that's implemented)
]);

echoable_message validate(echoable_message resp)
{
	//Filter the response to only that which is valid
	if (stringp(resp)) return resp;
	if (arrayp(resp)) switch (sizeof(resp))
	{
		case 0: return ""; //This should be dealt with at a higher level (and suppressed).
		case 1: return validate(resp[0]); //Collapse single element arrays to their sole element
		default: return validate(resp[*]) - ({""}); //Suppress any empty entries
	}
	if (!mappingp(resp)) return ""; //You can't really do much else, frankly. What are you trying to do, echo a float?
	mapping ret = (["message": validate(resp->message)]);
	if (ret->message == "") return ""; //No message? Nothing to do.
	//Whitelist the valid flags. Note that this will quietly suppress any empty
	//strings, which would be stating the default behaviour.
	foreach (valid_flags; string flag; multiset ok)
	{
		if (ok[resp[flag]]) ret[flag] = resp[flag];
	}
	//Since destinations can contain variable references and such, validate them separately.
	if (resp->dest && has_prefix(resp->dest, "/"))
	{
		sscanf(resp->dest, "/%[a-z] %[a-zA-Z$%]%s", string dest, string target, string empty);
		if ((<"w", "web", "set">)[dest] && target != "" && empty == "")
			ret->dest = sprintf("/%s %s", dest, target);
		//TODO: Ensure that "%" shows up only as "%s", and that dollar signs are
		//properly paired and surround legit variables
	}
	//Conditions have their own active ingredients.
	if (array parts = condition_parts[resp->conditional]) {
		foreach (parts + ({"conditional"}), string key)
			if (resp[key]) ret[key] = resp[key];
		ret->otherwise = validate(resp->otherwise);
	}
	//Delays are integer seconds. We'll permit a string of digits, since that might be
	//easier for the front end.
	if (resp->delay && resp->delay != "0" &&
			(intp(resp->delay) || (sscanf((string)resp->delay, "%[0-9]", string d) && d == resp->delay)))
		ret->delay = (int)resp->delay;
	if (sizeof(ret) == 1) return ret->message; //No flags? Just return the message.
	return ret;
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->request_type != "PUT") return (["error": 400]); //Probably an old client trying to POST the flags (no longer supported)
	if (!req->misc->is_mod) return (["error": 401]);
	mixed body = Standards.JSON.decode(req->body_raw);
	if (!body || !mappingp(body) || !stringp(body->cmdname)) return (["error": 400]);
	string cmd = String.trim(lower_case(body->cmdname) - "!");
	if (cmd == "") return (["error": 400]);
	cmd += req->misc->channel->name;
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic.
	mapping resp = validate(body);
	werror("FROM: %O\nTO: %O\n", body, resp);
	if (resp == "") return (["error": 400]); //Nothing left, probably stuff was invalid
	make_echocommand(cmd, resp);
	if (!mappingp(resp)) resp = (["message": resp]);
	return jsonify(resp);
}
