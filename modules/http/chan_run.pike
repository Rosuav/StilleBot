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
*/
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	mapping cfg = req->misc->channel->config;
	string nonce; mapping info;
	if (!cfg->monitors) ; //TODO: Give a nicer error?
	else if (mapping i = cfg->monitors[req->variables->nonce]) {
		nonce = req->variables->nonce;
		info = i;
	} else {
		//None specified? Find one that looks like a run bar.
		foreach (cfg->monitors; string n; mapping i) if (i->barcolor) {nonce = n; info = i; break;}
	}
	return render_template("chan_noobsrun.md", ([
		"channame": Standards.JSON.encode(req->misc->channel->name[1..]),
		"nonce": nonce || "",
		"css_attributes": G->G->monitor_css_attributes,
		"info": Standards.JSON.encode(info),
		"sample": Standards.JSON.encode(req->misc->channel->expand_variables(info->text)),
	]) | req->misc->chaninfo);
}

int message(object channel, mapping person, string msg)
{
	if (channel->name != "#cookingfornoobs") return 0;
	//In theory, this could be done with a !!cheer special command, except that
	//as of 20210120, specials don't have the full power of echo commands. Also,
	//the detection of StreamLabs messages has to be custom code, so we wouldn't
	//gain much anyway - only this first part could change.
	if (person->bits) channel->set_variable("rundistance", person->bits, "add");
	//if (person->user != "streamlabs") return 0; //temp hack
	werror("Got message: %O %O\n", person->user, msg);
	sscanf(msg, "%*s just tipped $%d.%d!", int dollars, int cents);
	cents += 100 * dollars;
	if (!cents) return 0; //Any non-matching lines will just look like $0.00
	channel->set_variable("rundistance", cents, "add"); //Both of these abuse the fact that it'll take an int just fine for add :)
	return 0;
}

protected void create(string name)
{
	register_hook("all-msgs", message);
	::create(name);
}
