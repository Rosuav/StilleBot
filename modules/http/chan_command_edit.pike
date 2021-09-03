//Deprecated
inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	function validate = function_object(G->G->http_endpoints->chan_command)->validate;
	if (req->request_type != "PUT") return (["error": 400]); //Probably an old client trying to POST the flags (no longer supported)
	if (!req->misc->is_mod) return (["error": 401]);
	mixed body = Standards.JSON.decode(req->body_raw);
	if (!body || !mappingp(body) || !stringp(body->cmdname)) return (["error": 400]);
	string cmd = String.trim(lower_case(body->cmdname) - "!");
	if (cmd == "") return (["error": 400]);
	cmd += req->misc->channel->name;
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic. NOTE: This is deprecated, and won't
	//work with everything; for instance, cooldowns will be broken.
	mapping resp = validate(body);
	//werror("FROM: %O\nTO: %O\n", body, resp);
	if (resp == "") return (["error": 400]); //Nothing left, probably stuff was invalid
	if (!req->misc->session->fake) make_echocommand(cmd, resp);
	if (!mappingp(resp)) resp = (["message": resp]);
	return jsonify(resp);
}
