inherit http_endpoint;
//Deprecated in favour of chan_monitors doing it all
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (req->request_type == "PUT") {
		//API back end to hot-update the value. It's actually a generic variable setter.
		//TODO: Is anything using this? If not, ditch it. If so, migrate it elsewhere.
		if (!req->misc->is_mod) return (["error": 401]); //JS wants it this way, not a redirect that a human would like
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body) || !stringp(body->var) || undefinedp(body->val)) return (["error": 400]);
		object chan = req->misc->channel;
		mapping vars = persist_status->path("variables")[chan->name] || ([]);
		//Forbid changing a variable that doesn't exist. This saves us the
		//trouble of making sure that it's a valid variable name too.
		string prev = vars["$" + body->var + "$"];
		if (!prev) return (["error": 404]);
		if (!req->misc->session->fake) req->misc->channel->set_variable(body->var, (string)(int)body->val);
		return jsonify((["prev": prev]));
	}
	return redirect("monitors");
}
