inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//NOTE: This could possibly cut out one round trip by returning the same thing that
	//twitchlogin would return, but there'd need to be some checks to ensure that the
	//session cookie has the correct path, and to make sure nothing else varies.
	if (!req->misc->session || !req->misc->session->user) return redirect("/twitchlogin?next=" + req->not_query);
	string c = req->misc->channel->name;
	mapping msgs = persist_status->path("private", c)[req->misc->session->user->id];
	if (!msgs) msgs = ([]);
	array text = values(msgs), times = indices(msgs);
	object user = user_text();
	sort(times, text);
	foreach (text; int i; string msg) //I actually want to map over zip(text, times) really
	{
		int tm = (int)times[i];
		text[i] = "* " + ctime(tm)[..<1] + ":<br>\n" + msg;
	}
	if (!sizeof(text)) text = ({"You have no private messages from this channel."});
	return render_template("chan_private.md", ([
		"user text": user,
		"messages": text * "\n",
		"recip": req->misc->session->user->display_name,
		"channel": req->misc->channel_name,
	]));
}
