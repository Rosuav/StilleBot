inherit http_websocket;
constant markdown = #"# Messages for $$recip$$ from channel $$channel$$

<div id=loading>Loading...</div>
<ul id=messages></ul>

<style>
li {line-height: 2.25;}
.date {
	padding-right: 0.25em;
}
.confirmdelete {
	min-width: 1.75em; height: 1.75em;
	padding: 0;
	margin-right: 0.25em;
}
</style>
";

/* TODO:
* Maybe have a concept of Unread, and consequently, have a Mark as Read button?
* Play around with formatting. Currently, emotes add a lot of height to a line.
* Maybe make the title customizable?? UI problem - what's a good non-annoying way to do it?
* Sort/group messages by month, or week, or by user?
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req)) return resp;
	return render(req, ([
		"vars": (["ws_group": req->misc->session->user->id]),
		"recip": req->misc->session->user->display_name,
	]) | req->misc->chaninfo);
}

mapping _get_message(string|int id, mapping msgs) {
	string|mapping msg = msgs[(string)id];
	if (!msg) return 0;
	if (stringp(msg)) msg = (["message": msg]); else msg = ([]) | msg;
	mapping emotes = G->G->emote_code_to_markdown;
	if (!msg->parts && emotes) {
		array parts = ({""});
		foreach (msg->message / " "; int i; string w)
			if (sscanf(w, "\uFFFAe%s:%s\uFFFB", string emoteid, string alt)) { //Assumes that emotes are always entire words, for simplicity
				string url = (int)emoteid ? "https://static-cdn.jtvnw.net/emoticons/v1/%s/1.0"
					: "https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/1.0";
				parts += ({(["type": "image", "url": sprintf(url, emoteid), "text": alt]), " "});
			}
			else if (emotes[w] && sscanf(emotes[w], "![%s](%s)", string alt, string url))
				parts += ({(["type": "image", "url": url, "text": alt]), " "});
			else if (hyperlink->match(w))
				parts += ({(["type": "link", "text": w]), " "});
			else parts[-1] += w + " ";
		parts[-1] = parts[-1][..<1]; //The last part will always end with a space.
		msg->parts = parts - ({""}); //The first and last entries could end up as empty strings.
	}
	if (!msg->received) msg->received = (int)id;
	msg->id = (string)id;
	return msg;
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	sscanf(msg->group, "%s#%s", string uid, string chan);
	if (conn->session->user->id != uid) return "Bad group ID"; //Shouldn't happen, but maybe if you refresh the page after logging in as a different user???
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping msgs = persist_status->path("private", channel->name)[grp];
	if (!msgs) return (["items": ({ })]);
	if (id) return _get_message(id, msgs);
	return (["items": _get_message(sort(indices(msgs))[*], msgs)]);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string uid, string chan);
	if (!G->G->irc->channels["#" + chan]) return;
	mapping msgs = persist_status->path("private", "#" + chan)[uid];
	if (!msgs) return;
	if (m_delete(msgs, (string)msg->id)) update_one(conn->group, msg->id);
	else conn->sock->send_text(Standards.JSON.encode((["cmd": "notify", "msg": "Deletion failed (already gone)"])));
}
