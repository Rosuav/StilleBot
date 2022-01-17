inherit http_websocket;
constant markdown = #"# Messages for $$recip$$ from channel $$channel$$

<div id=loading>Loading...</div>
<ul id=messages></ul>
<ul id=modmessages></ul>

[Mark all as read](:#mark_read)

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
.unread {
	font-weight: bold;
}
.acknowledge {margin-left: 0.375em;}
.soft-deleted {text-decoration: line-through;}
.soft-deleted .acknowledge {display: none;}

#modmessages li {
	background: #a0f0c0;
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
		"vars": ([
			"ws_group": req->misc->session->user->id,
			"ws_extra_group": req->misc->is_mod ? "-1" + req->misc->channel->name : 0,
		]),
		"recip": req->misc->session->user->display_name,
	]) | req->misc->chaninfo);
}

mapping _get_message(string|int id, mapping msgs) {
	string|mapping msg = msgs[(string)id];
	if (!msg) return 0;
	if (stringp(msg)) msg = (["message": msg]); else msg = ([]) | msg;
	if (msg->expiry && msg->expiry < time()) return 0;
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
	if (!msg->received) msg->received = time();
	//TODO: If msg->acknowledgement is a non-null non-string, flatten it to a string for the client.
	//Technically the acknowledgement could be any echoable_message, though it'll usually be either
	//null or a simple text string.
	msg->id = (string)id;
	return msg;
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	sscanf(msg->group, "%s#%s", string uid, string chan);
	if (uid == "-1") return !conn->is_mod && "Bad group ID"; //UID -1 is a pseudo-user for all mods to share
	if (conn->session->user->id != uid) return "Bad group ID"; //Shouldn't happen, but maybe if you refresh the page after logging in as a different user???
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping msgs = persist_status->path("private", channel->name)[grp];
	if (!msgs) return (["items": ({ })]);
	if (id) return _get_message(id, msgs);
	return (["items": _get_message(sort((array(int))indices(msgs) - ({0}))[*], msgs) - ({0})]);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	sscanf(conn->group, "%s#%s", string uid, string chan);
	if (!G->G->irc->channels["#" + chan]) return;
	mapping msgs = persist_status->path("private", "#" + chan)[uid];
	if (!msgs) return;
	if (m_delete(msgs, (string)msg->id)) update_one(conn->group, msg->id);
	else conn->sock->send_text(Standards.JSON.encode((["cmd": "notify", "msg": "Deletion failed (already gone)"])));
	persist_status->save();
}

void websocket_cmd_acknowledge(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	sscanf(conn->group, "%s#%s", string uid, string chan);
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return;
	mapping msgs = persist_status->path("private", "#" + chan)[uid];
	if (!msgs) return;
	mapping mail = m_delete(msgs, (string)msg->id);
	if (mail->acknowledgement) {
		mapping person = (["uid": (int)uid]);
		get_user_info((int)uid)->then() {mapping user = __ARGS__[0];
			if (!user) return;
			person->displayname = user->display_name;
			person->user = user->login;
			channel->send(person, mail->acknowledgement);
		};
	}
	if (mail) update_one(conn->group, msg->id);
	mapping msgmeta = msgs->_meta;
	if (msgmeta) msgmeta->lastread = msgmeta->lastid; //When you acknowledge any message, also mark all messages as serverside-read.
	persist_status->save();
}

void websocket_cmd_mark_read(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	sscanf(conn->group, "%s#%s", string uid, string chan);
	if (!G->G->irc->channels["#" + chan]) return;
	mapping msgmeta = persist_status->path("private", "#" + chan)[uid]->?_meta;
	if (!msgmeta) return;
	int was = msgmeta->lastread;
	msgmeta->lastread = msgmeta->lastid;
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "mark_read", "why": msg->why || "", "was": was, "now": msgmeta->lastread])));
}
