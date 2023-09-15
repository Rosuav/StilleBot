//Command manager
//Handles autocommands (repeat/automate), and the adding and removing of commands
//TODO: Migrate functionality from chan_commands into here eg validation and updating
inherit hook;
inherit annotated;
@retain: mapping autocommands = ([]);

//Convert a number of minutes into a somewhat randomized number of seconds
//Assumes a span of +/- 1 minute if not explicitly given
int seconds(int|array mins, string timezone) {
	if (!arrayp(mins)) mins = ({mins-1, mins+1, 0}); //Ancient compatibility mode. Shouldn't ever happen now.
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

void autospam(string channel, string msg) {
	if (function f = bounce(this_function)) return f(channel, msg);
	if (!G->G->stream_online_since[channel[1..]]) return;
	mapping cfg = get_channel_config(channel[1..]);
	if (!cfg) return; //Channel no longer configured
	echoable_message response = cfg->commands[?msg[1..]];
	int|array(int) mins = mappingp(response) && response->automate;
	if (!mins) return; //Autocommand disabled
	G->G->autocommands[msg[1..] + channel] = call_out(autospam, seconds(mins, cfg->timezone), channel, msg);
	if (response) msg = response;
	string me = persist_config["ircsettings"]->nick;
	G->G->irc->channels[channel]->send((["nick": me, "user": me]), msg);
}

@hook_channel_online: int connected(string channel) {
	mapping cfg = get_channel_config(channel); if (!cfg) return 0;
	foreach (cfg->commands || ([]); string cmd; echoable_message response) {
		if (!mappingp(response) || !response->automate) continue;
		mixed id = autocommands[cmd + "#" + channel];
		int next = id && find_call_out(id);
		if (undefinedp(next) || next > seconds(response->automate, cfg->timezone)) {
			if (next) remove_call_out(id); //If you used to have it run every 60 minutes, now every 15, cancel the current and retrigger.
			autocommands[cmd + "#" + channel] = call_out(autospam, seconds(response->automate, cfg->timezone), "#" + channel, "!" + cmd);
		}
	}
}

protected void create(string name) {
	::create(name);
	register_bouncer(autospam);
	foreach (list_channel_configs(), mapping cfg) if (cfg->login)
		if (G->G->stream_online_since[cfg->login]) connected(cfg->login);
}
