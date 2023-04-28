inherit http_websocket;
constant markdown = #"# Messages for $$recip$$ from channel $$channel$$

* [](:tag=input type=checkbox #select_all title=All/none) [Delete selected](:#delete_selected)
{:#header}

<div id=loading>Loading...</div>
<ul id=messages></ul>
<ul id=modmessages></ul>

[Mark all as read](:#mark_read)

<style>
main li {line-height: 2.25;}
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

#header {
	list-style-type: none;
	margin-bottom: -1em;
}
</style>
";

/* TODO:
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
	if (!msg->parts) {
		array parts = ({""});
		mapping botemotes = persist_status->path("bot_emotes");
		foreach (msg->message / " "; int i; string w)
			if (sscanf(w, "\uFFFAe%s:%s\uFFFB", string emoteid, string alt)) //Assumes that emotes are always entire words, for simplicity
				parts += ({(["type": "image", "url": emote_url(emoteid, 1), "text": alt]), " "});
			else if (botemotes[w])
				parts += ({(["type": "image", "url": emote_url(botemotes[w], 1), "text": w]), " "});
			else if (sscanf(w, "%s_%s", string base, string mod) && botemotes[base] && mod)
				parts += ({(["type": "image", "url": emote_url(botemotes[base] + "_" + mod, 1), "text": w]), " "});
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
	if (conn->session->user->?id != uid) return "Bad group ID"; //Shouldn't happen, but maybe if you refresh the page after logging in as a different user???
}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping msgs = persist_status->path("private", channel->name)[grp];
	if (!msgs) return (["items": ({ })]);
	if (id) return _get_message(id, msgs);
	return (["items": _get_message(sort((array(int))indices(msgs) - ({0}))[*], msgs) - ({0})]);
}

void wscmd_delete(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping msgs = persist_status->path("private", channel->name)[conn->subgroup];
	if (!msgs) return;
	if (m_delete(msgs, (string)msg->id)) update_one(conn->group, msg->id);
	else conn->sock->send_text(Standards.JSON.encode((["cmd": "notify", "msg": "Deletion failed (already gone)"])));
	persist_status->save();
}

void wscmd_acknowledge(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping msgs = persist_status->path("private", channel->name)[conn->subgroup];
	if (!msgs) return;
	mapping mail = m_delete(msgs, (string)msg->id);
	if (mail->acknowledgement) {
		mapping person = (["uid": (int)conn->subgroup]);
		get_user_info((int)conn->subgroup)->then() {mapping user = __ARGS__[0];
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

void wscmd_mark_read(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping msgmeta = persist_status->path("private", channel->name)[conn->subgroup]->?_meta;
	if (!msgmeta) return;
	int was = msgmeta->lastread;
	msgmeta->lastread = msgmeta->lastid;
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "mark_read", "why": msg->why || "", "was": was, "now": msgmeta->lastread])));
}
