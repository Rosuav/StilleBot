inherit http_websocket;
inherit builtin_command;

constant markdown = #"
# Channel Error Log

Errors that happen during bot operation will be shown here.

Show: <label><input type=checkbox name=show value=ERROR> Errors</label> <label><input type=checkbox name=show value=WARN> Warnings</label> <label><input type=checkbox name=show value=INFO> Info</label>

[Delete selected](:#deletemsgs)

<input type=checkbox id=selectall> | Timestamp | Level | Message | Context
--|-----------|-------|---------|---------
- | - | - | - | loading...
{:#msglog}

<style>
.hide-ERROR .lvl-ERROR {display: none;}
.hide-WARN .lvl-WARN {display: none;}
.hide-INFO .lvl-INFO {display: none;}
</style>
";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator status"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping err = await(G->G->DB->load_config(channel->userid, "errors"));
	if (id) {
		foreach (err->msglog || ({}), mapping msg)
			if (msg->id == id) return msg;
		return 0;
	}
	return ([
		"items": err->msglog || ({ }),
		//TODO: Allow the default visibility to be configured somewhere
		"visibility": err->visibility || ({"ERROR", "WARN"}),
		//Note: Don't remove this, even if the msgcount is better provided directly.
		//We want to let the channel object repopulate its own cache.
		"msgcount": await(channel->error_count(0)),
	]);
}

@"is_mod": void wscmd_delete(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {async_wscmd_delete(channel, conn, msg);}
__async__ void async_wscmd_delete(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping err = await(G->G->DB->load_config(channel->userid, "errors"));
	if (!arrayp(msg->ids) || !err->msglog) return;
	multiset ids = (multiset)msg->ids;
	err->msglog = filter(err->msglog) {return !ids[__ARGS__[0]->id];};
	await(G->G->DB->save_config(channel->userid, "errors", err));
	send_updates_all(conn->group);
}

constant builtin_description = "Log an error, warning, or informational";
constant builtin_name = "Log error";
constant builtin_param = ({"/Level/ERROR/WARN/INFO/THROW", "Message"});
constant vars_provided = ([]);
mapping message_params(object channel, mapping person, string|array param) {
	if (!arrayp(param)) param = ({"ERROR", param});
	if (param[0] == "THROW") error(param[1] + "\n");
	channel->report_error(param[0], param[1], ""); //TODO: Carry context through the message processing system
	return ([]);
}

__async__ void populate_demo_errors() {
	//If the demo channel exists, and if you've attempted to view its errors, and if it
	//doesn't actually have any, populate it with some examples.
	mapping err = await(G->G->DB->load_config(0, "errors"));
	object channel = G->G->irc->id[0];
	if (err && (!err->msglog || !sizeof(err->msglog))) {
		channel->report_error("ERROR", "No channel https://twitch.tv/!demo - is this actually the demo?", "");
		channel->report_error("WARN", "Unable to query moderator list for !demo", "/mods");
		channel->report_error("ERROR", "This command requires channel:manage:vips permission", "/vip mustardmine");
		channel->report_error("INFO", "Welcome to StilleBot!", "!hello");
		channel->report_error("INFO", "Messages like this can be viewed by the broadcaster and mods.", "!hello");
		channel->report_error("WARN", "The broadcaster may not give another Shoutout to the specified streamer until the cooldown period expires.", "/shoutout mustardmine");
		err->lastread = err->msglog[-1]->id;
	}
}

protected void create(string name) {
	::create(name);
	populate_demo_errors();
}
