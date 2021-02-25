inherit http_endpoint;

/* TODO:
* CitizenPrayer: Great :) To save space, maybe we can have the [message text] and the time stamp on the same line?
* Add a Delete button
* Maybe have a concept of Unread, and consequently, have a Mark as Read button?
* Add a websocket for live updates
* Retain emote IDs from incoming text somehow?? If the private text came from a chat command, it should in theory
  be possible to render the emotes from the command, rather than looking at the text for keywords.
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req)) return resp;
	string c = req->misc->channel->name;
	mapping msgs = persist_status->path("private", c)[req->misc->session->user->id];
	if (!msgs) msgs = ([]);
	array text = values(msgs), times = indices(msgs);
	object user = user_text();
	sort(times, text);
	foreach (text; int i; string msg) //I actually want to map over zip(text, times) really
	{
		int tm = (int)times[i];
		//TODO: Filter out really old ones maybe? Or highlight the most recent?
		text[i] = "* " + ctime(tm)[..<1] + ":<br>\n" + emotify_user_text(msg, user, 1);
	}
	if (!sizeof(text)) text = ({"You have no private messages from this channel."});
	return render_template("chan_private.md", ([
		"user text": user,
		"messages": text * "\n",
		"recip": req->misc->session->user->display_name,
	]) | req->misc->chaninfo);
}
