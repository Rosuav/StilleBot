inherit command;
constant require_moderator = 1;
//Note: Each special with the same-named parameter is assumed to use it in the same way.
//It's good to maintain this for the sake of humans anyway, but also the display makes
//this assumption, and has only a single description for any given name.
constant SPECIALS = ({
	({"!follower", ({"Someone follows the channel", "The new follower", ""}), "Stream support"}),
	({"!sub", ({"Someone subscribes for the first time", "The subscriber", "tier"}), "Stream support"}),
	({"!resub", ({"Someone announces a resubscription", "The subscriber", "tier, months, streak"}), "Stream support"}),
	({"!subgift", ({"Someone gives a sub", "The giver", "tier, months, streak, recipient, multimonth"}), "Stream support"}),
	({"!subbomb", ({"Someone gives random subgifts", "The giver", "tier, gifts"}), "Stream support"}),
	({"!cheer", ({"Any bits are cheered (including anonymously)", "The cheerer", "bits"}), "Stream support"}),
	({"!cheerbadge", ({"A viewer attains a new cheer badge", "The cheerer", "level"}), "Stream support"}),
	({"!raided", ({"Another broadcaster raided you", "The raiding broadcaster", "viewers"}), "Stream support"}),

	({"!channelonline", ({"The channel has recently gone online (started streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!channeloffline", ({"The channel has recently gone offline (stopped streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!musictrack", ({"A track just started playing (see VLC integration)", "VLC", "desc, blockpath, block, track, playing"}), "Status"}),

	({"!giveaway_started", ({"A giveaway just opened, and people can buy tickets", "The broadcaster", "title, duration, duration_hms, duration_english"}), "Giveaways"}),
	({"!giveaway_ticket", ({"Someone bought ticket(s) in the giveaway", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_toomany", ({"Ticket purchase attempt failed", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_closed", ({"The giveaway just closed; people can no longer buy tickets", "The broadcaster", "title, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_winner", ({"A giveaway winner has been chosen!", "The broadcaster", "title, winner_name, winner_tickets, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_ended", ({"The giveaway is fully concluded and all ticket purchases are nonrefundable.", "The broadcaster", "title, tickets_total, entries_total, giveaway_cancelled"}), "Giveaways"}),
});
constant SPECIAL_NAMES = (multiset)SPECIALS[*][0];
constant SPECIAL_PARAMS = ({
	({"tier", "Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)"}),
	({"months", "Cumulative months of subscription"}), //TODO: Check interaction with multimonth
	({"streak", "Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, but {streak} resets."}),
	({"recipient", "Display name of the gift sub recipient"}),
	({"multimonth", "Number of consecutive months of subscription given"}),
	({"gifts", "Number of randomly-assigned gifts. Can be 1."}),
	({"bits", "Total number of bits cheered in this message"}),
	({"level", "New badge level, eg 1000 if the 1K bits badge has just been attained"}),
	({"viewers", "Number of viewers arriving on the raid"}),
	({"uptime", "Stream broadcast duration - use {uptime|time_hms} or {uptime|time_english} for readable form"}),
	({"uptime_hms", "(deprecated) Equivalent to {uptime|time_hms}"}),
	({"uptime_english", "(deprecated) Equivalent to {uptime|time_english}"}),
	({"track", "Name of the audio file that's currently playing"}),
	({"block", "Name of the section/album/block of tracks currently playing, if any"}),
	({"blockpath", "Full path to the current block"}),
	({"desc", "Human-readable description of what's playing (block and track names)"}),
	({"playing", "1 if music is playing, or 0 if paused, stopped, disconnected, etc"}),
	({"title", "Title of the giveaway (eg the thing that can be won)"}),
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

multiset(string) update_aliases(string chan, string aliases, echoable_message response) {
	multiset updates = (<>);
	foreach (aliases / " ", string alias) {
		sscanf(alias, "%*[!]%[^#\n]", string safealias);
		if (safealias && safealias != "") {
			string cmd = safealias + "#" + chan;
			if (response) G->G->echocommands[cmd] = response;
			else m_delete(G->G->echocommands, cmd);
			updates[cmd] = 1;
		}
	}
	return updates;
}

//Update (or delete) an echo command and save them to disk
void make_echocommand(string cmd, echoable_message response, mapping|void extra)
{
	sscanf(cmd || "", "%[!]%s#%s", string pfx, string basename, string chan);
	multiset updates = (<cmd>);
	if (echoable_message prev = G->G->echocommands[cmd]) {
		//See if there are any aliases to be purged
		if (mappingp(prev) && prev->aliases) updates |= update_aliases(chan, prev->aliases, 0);
	}
	G->G->echocommands[cmd] = response;
	if (!response) m_delete(G->G->echocommands, cmd);
	if (mappingp(response) && response->aliases) updates |= update_aliases(chan, response->aliases, (response - (<"aliases">)) | (["alias_of": basename]));
	foreach (extra->?cooldowns || ([]); string cdname; int cdlength) {
		//If the cooldown delay is shorter than the cooldown timeout,
		//reset the timeout. That way, if you accidentally set a command
		//to have a really long timeout (eg an hour when you wanted a
		//minute), lowering the timeout will fix it. Note that any
		//cooldowns no longer part of the command won't be purged; at
		//worst, they'll linger in G->G until restart - no big deal.
		int timeout = G->G->cooldown_timeout[cdname + "#" + chan] - time();
		if (cdlength && timeout > cdlength) G->G->cooldown_timeout[cdname + "#" + chan] = cdlength + time();
	}
	string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
	Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
	if (object handler = chan && G->G->websocket_types->chan_commands) {
		//If the command name starts with "!", it's a special, to be
		//sent out to "!!#channel" and not to "#channel".
		foreach (updates; cmd;) {
			if (has_prefix(cmd, "!trigger#")) handler->send_updates_all("!" + cmd);
			else handler->update_one(pfx + pfx + "#" + chan, cmd);
			handler->send_updates_all(cmd);
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
		cmd = lower_case(cmd); //TODO: Switch this out for a proper Unicode casefold
		if (!SPECIAL_NAMES[cmd] && has_value(cmd, '!')) return "@$$: Command names cannot include exclamation marks";
		cmd += channel->name;
		string newornot = G->G->echocommands[cmd] ? "Updated" : "Created new";
		make_echocommand(cmd, response);
		return sprintf("@$$: %s command !%s", newornot, cmd - channel->name);
	}
	return "@$$: Try !addcmd !newcmdname response-message";
}

protected void create(string name)
{
	::create(name);
	G->G->echocommands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}");
	add_constant("make_echocommand", make_echocommand);
}
