inherit command;
constant featurename = "commands";
constant require_moderator = 1;
constant docstring = #"
Add a repeated command (autocommand) for this channel

Usage: `!repeat minutes text-to-send` or `!repeat minutes !command`

Creates an automated command for this channel. Every N minutes (randomized
a little each way to avoid emitting text in lock-step) while the channel is
live, the text will be sent to the channel, or the command will be run.
The time delay must be at least 5 minutes, but anything less than 20-30 mins
will be too spammy for most channels. Use this feature responsibly.

Commands can also be scheduled at a particular time (interpreted within your
configured time zone). If the channel is live at that time, the command will
be sent.

It's generally best to create autocommands based on [echo commands](addcmd),
as this will allow your mods and/or viewers to access the information directly
rather than waiting for the bot to offer it voluntarily. This also makes any
reconfiguration easy, as the autocommand is simple and easy to type.

Example: `!repeat 60 !uptime` - show the channel's live time roughly every hour

Example: `!repeat 30-60 !twitter` - show your Twitter link every 45 minutes, ish

Example: `!repeat 21:55 !raid` - remind you to go raiding at approx ending time

---

Usage: `!unrepeat text-to-send` or `!unrepeat !command`

Remove an autocommand. The command or text must exactly match something that
was previously set to repeat.

Both of these commands can be used while the channel is offline, but the
automated echoing will happen only while the stream is live.
";

//Convert a number of minutes into a somewhat randomized number of seconds
//Assumes a span of +/- 1 minute if not explicitly given
int seconds(int|array mins, string timezone)
{
	if (!arrayp(mins)) mins = ({mins-1, mins+1, 0});
	if (sizeof(mins) == 2) mins += ({0});
	switch (mins[2])
	{
		case 0: //Scheduled between X and Y minutes
			return mins[0] * 60 + random((mins[1]-mins[0]) * 60);
		case 1: //Scheduled at hh:mm in the user's timezone
		{
			//werror("Scheduling at %02d:%02d in %s\n", mins[0], mins[1], timezone);
			if (!timezone || timezone == "") timezone = "UTC";
			object now = Calendar.Gregorian.Second()->set_timezone(timezone);
			int target = mins[0] * 3600 + mins[1] * 60;
			target -= now->hour_no() * 3600 + now->minute_no() * 60 + now->second_no();
			if (target <= 0) target += 86400;
			return target;
		}
		default: return 86400; //Probably a bug somewhere.
	}
}
void autospam(string channel, string msg)
{
	if (function f = bounce(this_function)) return f(channel, msg);
	//TODO: Spam only if there's been text from someone other than the bot?
	//And if so, then how recently? Since the last time this echo command happened?
	//If we defer, do we skip an entire execution? Nothing's perfect here, so for
	//now, just keep it simple: repeated commands WILL repeat, no matter what.
	if (!G->G->stream_online_since[channel[1..]]) return;
	mapping cfg = persist_config["channels"][channel[1..]];
	if (!cfg) return; //Channel no longer configured
	int|array(int) mins = cfg->autocommands[msg];
	if (!mins) return; //Autocommand disabled
	string key = channel + " " + msg;
	G->G->autocommands[key] = call_out(autospam, seconds(mins, cfg->timezone), channel, msg);
	if (has_prefix(msg, "!"))
	{
		//If a command is given, pretend the bot typed it, and process as normal.
		object chan = G->G->irc->channels[channel];
		string me = persist_config["ircsettings"]->nick;
		chan->not_message((["nick": me, "user": me]), msg);
		return;
	}
	send_message(channel, msg);
}

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
		mins = ({m-1, m+1, 0}); //Repeated approx every X minutes
	if (!mins) return "Check https://rosuav.github.io/StilleBot/commands/repeat for usage information.";
	mapping ac = channel->config->autocommands;
	if (!ac) ac = channel->config->autocommands = ([]);
	string key = channel->name + " " + msg;
	if (mins[0] < 0)
	{
		//Normally spelled "!unrepeat some-message" but you can do it
		//as "!repeat -1 some-message" if you really want to
		if (!m_delete(ac, msg)) return "That message wasn't being repeated, and can't be cancelled";
		if (mixed id = m_delete(G->G->autocommands, key))
			remove_call_out(id);
		persist_config->save();
		return "Repeated command disabled.";
	}
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
	if (mixed id = m_delete(G->G->autocommands, key))
		remove_call_out(id);
	ac[msg] = mins;
	G->G->autocommands[key] = call_out(autospam, seconds(mins, channel->config->timezone), channel->name, msg);
	persist_config->save();
	return "Added to the repetition table.";
}

echoable_message unrepeat(object channel, mapping person, string param)
{
	return check_perms(channel, person, "-1 " + param);
}

int connected(string channel)
{
	mapping cfg = persist_config["channels"][channel];
	if (!cfg->autocommands) return 0;
	foreach (cfg->autocommands; string msg; int|array(int) mins)
	{
		string key = "#" + channel + " " + msg;
		mixed id = G->G->autocommands[key];
		if (!id || undefinedp(find_call_out(id)))
			G->G->autocommands[key] = call_out(autospam, seconds(mins, cfg->timezone), "#" + channel, msg);
	}
}

void check_autocommands()
{
	//First look for any that should be removed
	//No need to worry about channels being offline; they'll be caught at next repeat.
	foreach (G->G->autocommands; string key; mixed id)
	{
		sscanf(key, "%s %s", string channel, string msg);
		mapping cfg = persist_config["channels"][channel[1..]];
		if (!cfg || !cfg->autocommands[msg])
			remove_call_out(m_delete(G->G->autocommands, key));
	}
	//Next, look for any that need to be started.
	foreach (persist_config["channels"]; string channel; mapping cfg)
		connected(channel);
}

protected void create(string name)
{
	register_hook("channel-online", connected);
	register_bouncer(autospam);
	if (!G->G->autocommands) G->G->autocommands = ([]);
	check_autocommands();
	G->G->commands["unrepeat"] = unrepeat;
	::create(name);
}
