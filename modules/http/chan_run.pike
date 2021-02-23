inherit http_endpoint;

/*
1) Maintain a counter. Zero it at start of stream? If not, have a command to force it. May also be necessary for other situations.
2) On seeing a chat message from Streamlabs "Tchaikovsky just tipped $9.50!", add 950 to the counter.
3) On seeing any cheer, add the number of bits to the counter.
4) Maintain an array of per-mile thresholds, and (internally) partial sums.
5) Know which mile we are currently on. If that increments, give chat message: "devicatLvlup Mile #2 complete!! noobsGW"
6) Have a web integration. The maintained values will be variables and can go through that system. Full customization via web.
   - Bar colour, font/size, text colour, fill colour
   - Height, width? Or let OBS define that?
   - Do everything through the same websocket that monitor.js uses

TODO: Maybe govern the cents hiding with an option?

TODO: Allow the name of the next-mile command to be configured and selected.
Would require ALL commands (for this channel) to be sent. Would then be easy
to have a "None" option. In the drop-down, separately group any that refer to
the variable being used (but allow others, in case it's a static message).
*/
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (req->request_type == "PUT") {
		//API back end to hot-update the value. It's actually a generic variable setter.
		if (!req->misc->is_mod) return (["error": 401]); //JS wants it this way, not a redirect that a human would like
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body) || !stringp(body->var) || undefinedp(body->val)) return (["error": 400]);
		object chan = req->misc->channel;
		mapping vars = persist_status->path("variables")[chan->name] || ([]);
		//Forbid changing a variable that doesn't exist. This saves us the
		//trouble of making sure that it's a valid variable name too.
		string prev = vars["$" + body->var + "$"];
		if (!prev) return (["error": 404]);
		req->misc->channel->set_variable(body->var, (string)(int)body->val);
		return jsonify((["prev": prev]));
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	string nonce; mapping info;
	if (!cfg->monitors) ; //TODO: Give a nicer error?
	else if (mapping i = cfg->monitors[req->variables->nonce]) {
		nonce = req->variables->nonce;
		info = i;
	} else {
		//None specified? Find one that looks like a run bar.
		foreach (cfg->monitors; string n; mapping i) if (i->barcolor) {nonce = n; info = i; break;}
	}
	return render_template("chan_noobsrun.md", (["nonce": nonce || "", "vars": ([
		"channame": req->misc->channel->name[1..],
		"nonce": nonce || "",
		"css_attributes": G->G->monitor_css_attributes,
		"info": info,
		"display": req->misc->channel->expand_variables(info->text),
		"commands": (["nextmile": G->G->echocommands["nextmile" + req->misc->channel->name]]),
	])]) | req->misc->chaninfo);
}

int message(object channel, mapping person, string msg)
{
	if (channel->name != "#cookingfornoobs") return 0;
	int cents = person->bits;
	if (person->user == "streamlabs") {
		sscanf(msg, "%*s just tipped $%d.%d!", int dollars, cents);
		cents += 100 * dollars;
	}
	if (!cents) return 0; //Any non-matching lines will just look like $0.00
	channel->set_variable("rundistance", cents, "add"); //Abuse the fact that it'll take an int just fine for add :)
	if (cents < 0) return 0;
	//See if we've just hit a new mile. TODO: Handle this, and the incrementing
	//itself, more generically; it's a bit unnecessary to hard-code the variable
	//name, but I don't know if it'd actually work to have multiple. For instance,
	//what if there are multiple bars with different configs, but only one active
	//at a time? So for now, after finding one, we just stop.
	foreach (channel->config->monitors; ; mapping info) if (info->thresholds) {
		int total = (int)channel->expand_variables("$rundistance$");
		foreach (info->thresholds / " "; int mile; string th) {
			int nextmile = 100 * (int)th;
			if (total >= nextmile) {total -= nextmile; continue;}
			//This is the current mile. If we've only barely started it,
			//then we probably just hit this mile. (If mile is 0, we've
			//just broken positive after having a negative total.)
			if (total < cents) channel->send(person, G->G->echocommands["nextmile" + channel->name], (["%s": (string)mile]));
			break;
		}
		break;
	}
	return 0;
}

protected void create(string name)
{
	register_hook("all-msgs", message);
	::create(name);
}
