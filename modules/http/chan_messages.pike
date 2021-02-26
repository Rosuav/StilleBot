inherit http_endpoint;
inherit websocket_handler;

/* TODO:
* Maybe have a concept of Unread, and consequently, have a Mark as Read button?
* Play around with formatting. Currently, emotes add a lot of height to a line.
* Maybe make the title customizable?? UI problem - what's a good non-annoying way to do it?
* Abbreviate the timestamp and put the whole detail into hover text?
* Sort/group messages by month, or week, or by user?
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
	sort(times, text);
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

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	::websocket_msg(conn, msg);
	if (msg && msg->cmd == "delete") {
		sscanf(conn->group, "%s#%s", string uid, string chan);
		if (!G->G->irc->channels["#" + chan]) return;
		mapping msgs = persist_status->path("private", "#" + chan)[uid];
		if (!msgs) return;
		if (m_delete(msgs, msg->received)) send_updates_all(conn->group);
		else conn->sock->send_text(Standards.JSON.encode((["cmd": "notify", "msg": "Deletion failed (already gone)"])));
	}
}

protected void create(string name) {::create(name);}
