inherit http_endpoint;
inherit websocket_handler;

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
	return render_template("chan_messages.md", ([
		"vars": (["ws_type": "chan_messages", "ws_group": req->misc->session->user->id + req->misc->channel->name]),
		"recip": req->misc->session->user->display_name,
	]) | req->misc->chaninfo);
}

mapping get_state(string group) {
	sscanf(group, "%s#%s", string uid, string chan);
	if (!G->G->irc->channels["#" + chan]) return 0;
	mapping msgs = persist_status->path("private", "#" + chan)[uid];
	if (!msgs) return (["messages": ({ })]);
	array text = values(msgs), times = indices(msgs);
	sort(times, text); //FIXME: Is this sorting by the string representations of Unix time? Would become a problem in 2286 AD.
	array ret = ({ });
	mapping emotes = G->G->emote_code_to_markdown;
	foreach (text; int i; string|mapping msg) {
		if (stringp(msg)) msg = (["message": msg]); else msg = ([]) | msg;
		if (!msg->parts && emotes) {
			array parts = ({""});
			foreach (msg->message / " "; int i; string w)
				if (sscanf(w, "\uFFFAe%d:%s\uFFFB", int id, string alt)) //Assumes that emotes are always entire words, for simplicity
					parts += ({(["type": "image", "url": "https://static-cdn.jtvnw.net/emoticons/v1/" + id + "/1.0", "text": alt]), " "});
				else if (emotes[w] && sscanf(emotes[w], "![%s](%s)", string alt, string url))
					parts += ({(["type": "image", "url": url, "text": alt]), " "});
				else if (hyperlink->match(w))
					parts += ({(["type": "link", "text": w]), " "});
				else parts[-1] += w + " ";
			parts[-1] = parts[-1][..<1]; //The last part will always end with a space.
			msg->parts = parts - ({""}); //The first and last entries could end up as empty strings.
		}
		msg->received = times[i];
		ret += ({msg});
	}
	return (["messages": ret]);
}

protected void create(string name) {::create(name);}
