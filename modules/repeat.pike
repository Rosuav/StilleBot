inherit command;
inherit hook; //Ensure that residual hooks get purged
constant featurename = "commands";
constant require_moderator = 1;
constant docstring = #"
Add a repeated command (autocommand) for this channel

Usage: `!repeat minutes !command`

Creates an automated command for this channel. Every N minutes (randomized
a little each way to avoid emitting text in lock-step) while the channel is
live, the command will be run.
The time delay must be at least 5 minutes, but anything less than 20-30 mins
will be too spammy for most channels. Use this feature responsibly.

Commands can also be scheduled at a particular time (interpreted within your
configured time zone). If the channel is live at that time, the command will
be sent.

Automated commands are defined as [echo commands](addcmd), which conveniently
allows your mods and/or viewers to access the information directly
rather than waiting for the bot to offer it voluntarily. This also makes any
reconfiguration easy, as the autocommand is simple and easy to type.

Example: `!repeat 60 !uptime` - show the channel's live time roughly every hour

Example: `!repeat 30-60 !twitter` - show your Twitter link every 45 minutes, ish

Example: `!repeat 21:55 !raid` - remind you to go raiding at approx ending time

---

Usage: `!unrepeat !command`

Remove an autocommand. The command must exactly match something that
was previously set to repeat.

Both of these commands can be used while the channel is offline, but the
automated echoing will happen only while the stream is live.
";
void autospam(string channel, string msg) { }

echoable_message process(object channel, mapping person, string param)
{
	if (param == "")
	{
		//TODO: Report all current repeated messages
		//Or link to the web info if there's a server running.
		return "(unimpl)";
	}
	array(int) mins;
	string msg;
	if (sscanf(param, "%d:%d %s", int hr, int min, msg) && msg)
		mins = ({hr, min, 1}); //Scheduled at hh:mm
	else if (sscanf(param, "%d-%d %s", int min, int max, msg) && msg)
		mins = ({min, max, 0}); //Repeated between X and Y minutes
	else if (sscanf(param, "%d %s", int m, msg) && msg)
		mins = ({m, m, 0}); //Repeated exactly every X minutes
	if (!mins) return "Check https://rosuav.github.io/StilleBot/commands/repeat for usage information.";
	//Currently, if you say "!repeat 20-30 commandname", it will error out rather than
	//search for "!commandname". Would be convenient if it could search; do this later.
	if (!msg || msg == "" || msg[0] != '!') return "Usage: !repeat x-y !commandname - see https://rosuav.github.io/StilleBot/commands/repeat";
	echoable_message command = channel->commands[msg[1..]];
	if (mins[0] < 0) {
		if (!mappingp(command) || !command->automate) return "That message wasn't being repeated, and can't be cancelled";
		//Copy the command, remove the automation, and do a standard validation
		G->G->update_command(channel, "", msg, command - (<"automate">));
		return "Command will no longer run automatically.";
	}
	if (!command) return "Command not found (add it using !addcmd first)";
	switch (mins[2])
	{
		case 0:
			if (mins[0] < 5) return "Minimum five-minute repeat cycle. You should probably keep to a minimum of 20 mins.";
			if (mins[1] < mins[0]) return "Maximum period must be at least the minimum period.";
			break;
		case 1:
			if (mins[0] < 0 || mins[0] >= 24 || mins[1] < 0 || mins[1] >= 60)
				return "Time must be specified as hh:mm (in your local timezone).";
			break;
		default: return "Huh?"; //Shouldn't happen
	}
	if (!mappingp(command)) command = (["message": command]);
	G->G->update_command(channel, "", msg, command | (["automate": mins]));
	return "Command " + msg + " will now be run automatically.";
}

echoable_message unrepeat(object channel, mapping person, string param)
{
	return check_perms(channel, person, "-1 " + param);
}

protected void create(string name)
{
	::create(name);
	register_bouncer(autospam);
	G->G->commands["unrepeat"] = unrepeat;
}
