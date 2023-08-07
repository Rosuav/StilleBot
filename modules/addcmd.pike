inherit command;
constant featurename = "commands";
constant require_moderator = 1;
//Note: Each special with the same-named parameter is assumed to use it in the same way.
//It's good to maintain this for the sake of humans anyway, but also the display makes
//this assumption, and has only a single description for any given name.
constant SPECIALS = ({
	({"!follower", ({"Someone follows the channel", "The new follower", ""}), "Stream support"}),
	({"!sub", ({"Someone subscribes for the first time", "The subscriber", "tier, multimonth"}), "Stream support"}),
	({"!resub", ({"Someone announces a resubscription", "The subscriber", "tier, months, streak, multimonth, msg"}), "Stream support"}),
	({"!subgift", ({"Someone gives a sub", "The giver", "tier, months, streak, recipient, multimonth, from_subbomb"}), "Stream support"}),
	({"!subbomb", ({"Someone gives random subgifts", "The giver", "tier, gifts"}), "Stream support"}),
	({"!cheer", ({"Any bits are cheered (including anonymously)", "The cheerer", "bits, msg, msgid"}), "Stream support"}),
	({"!cheerbadge", ({"A viewer attains a new cheer badge", "The cheerer", "level"}), "Stream support"}),
	({"!raided", ({"Another broadcaster raided you", "The raiding broadcaster", "viewers"}), "Stream support"}),
	({"!charity", ({"Someone donates to the charity you're supporting", "The donor", "amount, msgid"}), "Stream support"}),

	({"!channelonline", ({"The channel has recently gone online (started streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!channelsetup", ({"The channel is online and has recently changed its category/title/tags", "The broadcaster", "category, title, tag_names, ccls"}), "Status"}),
	({"!channeloffline", ({"The channel has recently gone offline (stopped streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!musictrack", ({"A track just started playing (see VLC integration)", "VLC", "desc, blockpath, block, track, playing"}), "Status"}),

	({"!giveaway_started", ({"A giveaway just opened, and people can buy tickets", "The broadcaster", "title, duration, duration_hms, duration_english"}), "Giveaways"}),
	({"!giveaway_ticket", ({"Someone bought ticket(s) in the giveaway", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_toomany", ({"Ticket purchase attempt failed", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_closed", ({"The giveaway just closed; people can no longer buy tickets", "The broadcaster", "title, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_winner", ({"A giveaway winner has been chosen!", "The broadcaster", "title, winner_name, winner_tickets, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_ended", ({"The giveaway is fully concluded and all ticket purchases are nonrefundable.", "The broadcaster", "title, tickets_total, entries_total, giveaway_cancelled"}), "Giveaways"}),

	({"!kofi_dono", ({"Donation received on Ko-fi.", "The broadcaster", "amount, msg, from_name"}), "Ko-fi"}),
	({"!kofi_member", ({"New monthly membership on Ko-fi.", "The broadcaster", "amount, msg, from_name, tiername"}), "Ko-fi"}),
	({"!kofi_shop", ({"Shop sale on Ko-fi.", "The broadcaster", "amount, msg, from_name, shop_item_ids"}), "Ko-fi"}),
});
constant SPECIAL_NAMES = (multiset)SPECIALS[*][0];
constant SPECIAL_PARAMS = ({
	({"tier", "Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)"}),
	({"months", "Cumulative months of subscription"}), //TODO: Check interaction with multimonth
	({"streak", "Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, but {streak} resets."}),
	({"recipient", "Display name of the gift sub recipient"}),
	({"multimonth", "Number of consecutive months of subscription given"}),
	({"msg", "Any message included with the sub/cheer/dono (blank if none)"}),
	({"msgid", "UUID of the message, suitable for replies etc"}),
	({"from_subbomb", "1 if the gift was part of a sub bomb, 0 if not"}),
	({"gifts", "Number of randomly-assigned gifts. Can be 1."}),
	({"bits", "Total number of bits cheered in this message"}),
	({"level", "New badge level, eg 1000 if the 1K bits badge has just been attained"}),
	({"viewers", "Number of viewers arriving on the raid"}),
	({"uptime", "Stream broadcast duration - use {uptime|time_hms} or {uptime|time_english} for readable form"}),
	({"uptime_hms", "(deprecated) Equivalent to {uptime|time_hms}"}),
	({"uptime_english", "(deprecated) Equivalent to {uptime|time_english}"}),
	({"category", "English name of the game or category being streamed in"}),
	({"tag_names", "Stream tags eg '[English], [FamilyFriendly]' - should be searched case insensitively"}),
	({"ccls", "Content classification labels eg '[ProfanityVulgarity], [ViolentGraphic]'"}),
	({"track", "Name of the audio file that's currently playing"}),
	({"block", "Name of the section/album/block of tracks currently playing, if any"}),
	({"blockpath", "Full path to the current block"}),
	({"desc", "Human-readable description of what's playing (block and track names)"}),
	({"playing", "1 if music is playing, or 0 if paused, stopped, disconnected, etc"}),
	({"title", "Title of the stream or giveaway (eg the thing that can be won)"}),
	({"duration", "How long the giveaway will be open (seconds; 0 means open until explicitly closed)"}),
	({"duration_hms", "(deprecated) Equivalent to {duration|time_hms}"}),
	({"duration_english", "(deprecated) Equivalent to {duration|time_english}"}),
	({"tickets_bought", "Number of tickets just bought (or tried to)"}),
	({"tickets_total", "Total number of tickets bought"}),
	({"tickets_max", "Maximum number of tickets any single user may purchase"}),
	({"entries_total", "Total number of unique people who entered"}),
	({"winner_name", "Name of the person who won - blank if no tickets purchased"}),
	({"winner_tickets", "Number of tickets the winner had purchased"}),
	({"giveaway_cancelled", "1 if the giveaway was cancelled (refunding all tickets), 0 if not (normal ending)"}),
	({"amount", "Total amount given (with currency eg '3 USD')"}),
	({"from_name", "Name (possibly username) of the Ko-fi supporter. Not (necessarily) a Twitch username."}),
	({"shop_item_ids", "Blank-separated list of ten-digit hexadecimal item IDs bought."}),
	({"tiername", "Ko-fi subscription tier (if applicable)"}),
});
constant docstring = sprintf(#"
Add an echo command for this channel

Usage: `!addcmd !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Echo commands themselves are available to everyone in the channel, and simply
display the text they have been given. The marker `%%s` will be replaced with
whatever additional words are given with the command, if any. Similarly, `$$`
is replaced with the username of the person who triggered the command.

Special usage: `!addcmd !!specialaction text-to-echo`

Pseudo-commands are not executed in the normal way, but are triggered on
certain events. The special action must be one of the following:

Special name | When it happens             | Initiator (`$$`) | Other info
-------------|-----------------------------|------------------|-------------
%{!%s%{ | %s%}
%}

Each special action has its own set of available parameters, which can be
inserted into the message, used in conditionals, etc. They are always enclosed
in braces, and have meanings as follows:

Parameter    | Meaning
-------------|------------------
%{{%s} | %s
%}

Editing these special commands can also be done via the bot's web browser
configuration pages, where available.
", SPECIALS, SPECIAL_PARAMS);

void update_aliases(object channel, string aliases, echoable_message response, multiset updates) {
	foreach (aliases / " ", string alias) {
		sscanf(alias, "%*[!]%[^#\n]", string safealias);
		if (safealias && safealias != "" && (!mappingp(response) || safealias != response->alias_of)) {
			string cmd = safealias + channel->name;
			if (response) channel->commands[safealias] = response;
			else {m_delete(G->G->echocommands, cmd); m_delete(channel->commands, safealias);}
			updates[cmd] = 1;
		}
	}
}

void purge(object channel, string cmd, multiset updates) {
	echoable_message prev = m_delete(channel->commands, cmd) || m_delete(G->G->echocommands, cmd + channel->name);
	m_delete(channel->path("commands"), cmd);
	if (prev) updates[cmd + channel->name] = 1;
	if (!mappingp(prev)) return;
	if (prev->alias_of) purge(channel, prev->alias_of, updates);
	if (prev->aliases) update_aliases(channel, prev->aliases, 0, updates);
	if (prev->automate) {
		//Clear out the timer
		mixed id = m_delete(G->G->autocommands, cmd + channel->name);
		if (id) remove_call_out(id);
	}
	if (prev->redemption) {
		channel->redemption_commands[prev->redemption] -= ({cmd});
		if (!sizeof(channel->redemption_commands[prev->redemption])) m_delete(channel->redemption_commands, prev->redemption);
		updates["rew " + prev->redemption] = 1;
	}
}

//Update (or delete) a per-channel echo command and save to disk
void make_echocommand(string cmd, echoable_message response, mapping|void extra)
{
	sscanf(cmd || "", "%[!]%s#%s", string pfx, string basename, string chan);
	object channel = G->G->irc->channels["#" + chan]; if (!channel) error("Requires a channel name.\n");
	multiset updates = (<cmd>);
	purge(channel, pfx + basename, updates);
	if (sscanf(extra->?original || "", "%s#", string oldname)) purge(channel, oldname, updates); //Renaming a command requires removal of what used to be.
	//Purge any iteration variables that begin with ".basename:" - anonymous rotations restart on
	//any edit. This ensures that none of the anonymous ones hang around. Named ones are regular
	//variables, though, and might be shared, so we don't delete those.
	mapping vars = persist_status->has_path("variables", channel);
	string remove = "$." + basename + ":";
	if (vars) foreach (indices(vars), string v) if (has_prefix(v, remove)) {
		m_delete(vars, v);
		if (object handler = G->G->websocket_types->chan_variables)
			handler->update_one(channel->name, v - "$");
	}
	if (response) channel->commands[pfx + basename] = channel->path("commands")[pfx + basename] = response;
	if (mappingp(response) && response->aliases) update_aliases(channel, response->aliases, (response - (<"aliases">)) | (["alias_of": basename]), updates);
	foreach (extra->?cooldowns || ([]); string cdname; int cdlength) {
		//If the cooldown delay is shorter than the cooldown timeout,
		//reset the timeout. That way, if you accidentally set a command
		//to have a really long timeout (eg an hour when you wanted a
		//minute), lowering the timeout will fix it. Note that any
		//cooldowns no longer part of the command won't be purged; at
		//worst, they'll linger in G->G until restart - no big deal.
		int timeout = G->G->cooldown_timeout[cdname + channel->name] - time();
		if (cdlength && timeout > cdlength) G->G->cooldown_timeout[cdname + channel->name] = cdlength + time();
	}
	if (mappingp(response) && response->automate && G->G->stream_online_since[channel->login]) {
		//Start a timer
		//Currently, a simple hack: notify repeat.pike to recheck everything.
		function repeat = G->G->commands->repeat;
		if (repeat) function_object(repeat)->connected(channel->login);
	}
	if (mappingp(response) && response->redemption) {
		channel->redemption_commands[response->redemption] += ({basename});
		updates["rew " + response->redemption] = 1;
	}
	//Write out the global echocommands in case it's changed (it usually won't and is deprecated anyway)
	string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
	Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
	persist_config->save(); //FIXME-SEPCHAN: Save the specific channel's config
	if (object handler = G->G->websocket_types->chan_commands) {
		//If the command name starts with "!", it's a special, to be
		//sent out to "!!#channel" and not to "#channel".
		foreach (updates; cmd;) {
			//TODO maybe: If a command has been renamed, notify clients to rename, rather than
			//deleting the old and creating the new.
			if (has_prefix(cmd, "rew ")) continue;
			if (has_prefix(cmd, "!trigger#")) handler->send_updates_all("!" + cmd);
			else handler->update_one(pfx + pfx + channel->name, cmd);
			handler->send_updates_all(cmd);
		}
	}
	if (object handler = G->G->websocket_types->chan_pointsrewards) {
		//Similarly to the above, notify changes to any redemption invocations.
		foreach (updates; cmd;) {
			if (!has_prefix(cmd, "rew ")) continue;
			//update_one not currently supported on this socket, so just
			//send a full update and then stop (so we don't multiupdate).
			handler->send_updates_all(channel->name); break;
		}
	}
}

string process(object channel, object person, string param)
{
	if (sscanf(param, "!%[^# ] %s", string cmd, string response) == 2)
	{
		//Create a new command. Note that it *always* gets the channel name appended,
		//making it a channel-specific command; global commands can only be created by
		//manually editing the JSON file.
		cmd = command_casefold(cmd);
		if (!SPECIAL_NAMES[cmd] && has_value(cmd, '!')) return "@$$: Command names cannot include exclamation marks";
		string newornot = channel->commands[cmd] ? "Updated" : "Created new";
		make_echocommand(cmd + channel->name, response);
		return sprintf("@$$: %s command !%s", newornot, cmd);
	}
	return "@$$: Try !addcmd !newcmdname response-message";
}

protected void create(string name)
{
	::create(name);
	//Load legacy and global echocommands. New channel-specific commands belong in channel config instead.
	G->G->echocommands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}");
	foreach (G->G->echocommands; string cmd; echoable_message response)
		if (has_value(cmd, "#")) catch {make_echocommand(cmd, response);}; //Migrate all channel-specific commands.
	add_constant("make_echocommand", make_echocommand);
}
