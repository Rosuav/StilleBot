inherit command;
constant require_moderator = 1;
//TODO: Reword these, or maybe change the layout of the docstring. The web interface
//now has a very different layout, which makes the current content look ugly.
//Maybe separate the names from their meanings, and in the text version, put all the
//meanings down below, separately, but in the web, have them together? Would require
//each name to mean the same thing if it's used in multiple specials, but that's OK,
//I think, given that it'd be confusing for humans to do otherwise anyway.
constant SPECIALS = ({
	({"!follower", ({"Someone follows the channel", "The new follower", ""})}),
	({"!sub", ({"Brand new subscription", "The subscriber", "{tier} (1, 2, or 3)"})}),
	({"!resub", ({"Resub is announced", "The subscriber", "{tier}, {months}, {streak}"})}),
	({"!subgift", ({"Someone gives a sub", "The giver", "{tier}, {months}, {streak}, {recipient}, {multi}"})}),
	({"!subbomb", ({"Someone gives many subgifts", "The giver", "{tier}, {gifts}"})}),
	({"!cheer", ({"Any bits are cheered (including anonymously)", "The giver", "{bits}"})}),
	({"!cheerbadge", ({"A viewer attains a new cheer badge", "The cheerer", "{level} - badge for N bits"})}),
});
constant SPECIAL_NAMES = (multiset)SPECIALS[*][0];
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

Editing these special commands can also be done via the bot's web browser
configuration pages, where available.
", SPECIALS);

//Update (or delete) an echo command and save them to disk
void make_echocommand(string cmd, echoable_message response)
{
	G->G->echocommands[cmd] = response;
	if (!response) m_delete(G->G->echocommands, cmd);
	string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
	Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
	sscanf(cmd || "", "%[!]%*s#%s", string pfx, string chan);
	if (object handler = chan && G->G->websocket_types->chan_commands) {
		//If the command name starts with "!", it's a special, to be
		//sent out to "!!#channel" and not to "#channel".
		handler->update_one(pfx + pfx + "#" + chan, cmd);
		handler->send_updates_all(cmd);
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
