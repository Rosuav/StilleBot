inherit http_websocket;
constant markdown = #"# Master Control Panel for $$channel$$

From here, you can make all kinds of really important changes. Maybe.

> ### Danger Zone
>
> Caution: These settings may break things!
>
> Deactivate the bot completely. This will remove the bot from your channel and
> disable the web configuration pages. To reinstate the bot, you will need to
> reauthenticate and reactivate it. [Deactivate](:#deactivate)
{: tag=hgroup #dangerzone}

<style>
#dangerzone {
	margin: 4px;
	border: 5px double red;
	padding: 8px;
}
</style>

> [Export/back up all configuration](:type=submit name=export)
{:tag=form method=post}

<!-- -->

> ### Deactivate account
>
> Are you SURE you wish to deactivate your account? This will remove the bot from
> your channel, disable all these web configuration pages, and delete all your
> settings as stored on the server.
>
> To confirm, enter the exact Twitch channel name here: <input data-expect=\"$$channel$$\" autocomplete=off> <code>$$channel$$</code>
>
> To further confirm, enter the name of the bot you wish to remove: <input data-expect=\"Mustard Mine\" autocomplete=off> <code>Mustard Mine</code>
>
> [Yes, do as I say](:#deactivateaccount disabled=true) [No, didn't mean that](:.dialog_close)
{: tag=dialog #deactivatedlg}
";

/* Other things to potentially add here:

* Support ticket. Options include feature request, bug report, and outage notification. If I, as admin,
  flag the user as trusted, "outage notification" will cause a scream at Sikorsky (as per my own alerts).
* Timezone setting, migrated from /features

*/

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "that the broadcaster use it"]) | req->misc->chaninfo);
	if (req->misc->session->fake) return render(req, (["js": "chan_mastercontrol"]) | req->misc->chaninfo);
	if ((int)req->misc->session->user->id != req->misc->channel->userid
		//&& !is_localhost_mod(req->misc->session->user->login, req->get_ip()) //Uncomment to allow localhost override for this page (not normally)
	) return render_template("login.md", (["msg": "that the broadcaster use it. It contains settings so dangerous they are not available to mods. Sorry! If you ARE the broadcaster, please reauthenticate"]) | req->misc->chaninfo);
	if (req->request_type == "POST" && req->variables->export) {
		object channel = req->misc->channel;
		mapping cfg = channel->config;
		mapping ret = ([]);
		//Save any exportable configs. This will cover a lot of things, but not those that
		//are in separate tables.
		foreach (await(G->G->DB->query_ro(#"select * from stillebot.config
			join stillebot.config_exportable on stillebot.config.keyword = stillebot.config_exportable.keyword
			where twitchid = :twitchid", (["twitchid": channel->userid]))), mapping cfg)
				if (sizeof(cfg->data)) ret[cfg->keyword] = cfg->data;
		mapping commands = ([]), specials = ([]);
		string chan = channel->name[1..];
		foreach (channel->commands || ([]); string cmd; echoable_message response) {
			if (mappingp(response) && response->alias_of) continue;
			if (has_prefix(cmd, "!")) specials[cmd] = response;
			else commands[cmd] = response;
		}
		ret->commands = commands;
		if (array t = m_delete(specials, "!trigger"))
			if (arrayp(t)) ret->triggers = t;
		ret->specials = specials;
		mapping resp = jsonify(ret, 5);
		string fn = "stillebot-" + channel->name[1..] + ".json";
		resp->extra_heads = (["Content-disposition": sprintf("attachment; filename=%q", fn)]);
		return resp;
	}
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if ((int)conn->session->user->?id != channel->?userid) return "Broadcaster only";
	return ::websocket_validate(conn, msg);
}

mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]); //Only using the ws for command signalling currently.
}

void websocket_cmd_deactivate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return;
	//Final confirmation: this really IS being done by the broadcaster
	//Shouldn't be necessary as the websocket won't validate else, but still. Paranoia.
	if ((int)conn->session->user->?id != channel->userid) return;
	Stdio.append_file("activation.log", sprintf("[%d] Account deactivated by broadcaster request: uid %d login %O\n", time(), channel->userid, channel->login));
	//Alright. Let's leave that channel.
	int chanid = channel->userid;
	channel->remove_bot_from_channel();
	//Find all websockets for this channel and kick them.
	foreach (G->G->websocket_groups;; mapping groups) foreach (groups; string|int grp; array socks) {
		if (stringp(grp) && has_suffix(grp, "#" + chanid))
			conn->sock->send_text(Standards.JSON.encode(([
				"cmd": "*DC*",
				"error": "Channel deactivated.",
			])));
	}
}
