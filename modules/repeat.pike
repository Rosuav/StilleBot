inherit command;
constant require_moderator = 1;
constant docstring = #"
Add a repeated command (autocommand) for this channel

Usage: `!repeat minutes text-to-send` or `!repeat minutes !command`

Creates an automated command for this channel. Every N minutes (randomized
a little each way to avoid emitting text in lock-step) while the channel is
live, the text will be sent to the channel, or the command will be run.
The time delay must be at least 5 minutes, but anything less than 20-30 mins
will be too spammy for most channels. Use this feature responsibly.

It's generally best to create autocommands based on [echo commands](addcmd),
as this will allow your mods and/or viewers to access the information directly
rather than waiting for the bot to offer it voluntarily. This also makes any
reconfiguration easy, as the autocommand is simple and easy to type.

---

Usage: `!unrepeat text-to-send` or `!unrepeat !command`

Remove an autocommand. The command or text must exactly match something that
was previously set to repeat.

Both of these commands can be used while the channel is offline, but the
automated echoing will happen only while the stream is live.
";

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
	int mins = cfg->autocommands[msg];
	if (!mins) return; //Autocommand disabled
	string key = channel + " " + msg;
	G->G->autocommands[key] = call_out(autospam, mins * 60 - 60 + random(120), channel, msg); //plus or minus a minute
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

echoable_message process(object channel, object person, string param)
{
	if (param == "")
	{
		//TODO: Report all current repeated messages
		return "(unimpl)";
	}
	sscanf(param, "%d %s", int mins, string msg);
	if (!mins || !msg) return "Check https://rosuav.github.io/StilleBot/commands/repeat for usage information.";
	mapping ac = channel->config->autocommands;
	if (!ac) ac = channel->config->autocommands = ([]);
	string key = channel->name + " " + msg;
	if (mins == -1)
	{
		//Normally spelled "!unrepeat some-message" but you can do it
		//as "!repeat -1 some-message" if you really want to
		if (!m_delete(ac, msg)) return "That message wasn't being repeated, and can't be cancelled";
		if (mixed id = m_delete(G->G->autocommands, key))
			remove_call_out(id);
		return "Repeated command disabled.";
	}
	if (mins < 5) return "Minimum five-minute repeat cycle. You should probably keep to a minimum of 20 mins.";
	if (mixed id = m_delete(G->G->autocommands, key))
		remove_call_out(id);
	ac[msg] = mins;
	G->G->autocommands[key] = call_out(autospam, mins * 60, channel->name, msg);
	return "Added to the repetition table.";
}

echoable_message unrepeat(object channel, object person, string param)
{
	return process(channel, person, "-1 " + param);
}

int connected(string channel)
{
	mapping ac = persist_config["channels"][channel]->autocommands;
	if (!ac) return 0;
	foreach (ac; string msg; int mins)
	{
		string key = "#" + channel + " " + msg;
		mixed id = G->G->autocommands[key];
		if (!id || undefinedp(find_call_out(id)))
			G->G->autocommands[key] = call_out(autospam, mins * 60 - 60 + random(120), "#" + channel, msg);
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

void create(string name)
{
	register_hook("channel-online", connected);
	register_bouncer(autospam);
	if (!G->G->autocommands) G->G->autocommands = ([]);
	else check_autocommands();
	G->G->commands["unrepeat"] = unrepeat;
	::create(name);
}
