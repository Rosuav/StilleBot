void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
}

class command
{
	constant all_channels = 0; //Set to 1 if this command should be available even if allcmds is not set for the channel
	constant require_moderator = 0; //Set to 1 if the command is mods-only
	constant active_channels = ({ }); //To restrict this to some channels only, set this to a non-empty array.
	//Override this to do the command's actual functionality, after permission checks.
	//Return a string to send that string, with "@$$" to @-notify the user.
	string|array(string) process(object channel, object person, string param) { }

	//Make sure that inappropriate commands aren't called. Normally these
	//checks are done in find_command below, but it's cheap to re-check.
	//(Maybe remove this and depend on find_command??)
	string|array(string) check_perms(object channel, object person, string param)
	{
		if (!all_channels && !channel->config->allcmds) return 0;
		if (require_moderator && !channel->mods[person->user]) return 0;
		return process(channel, person, param);
	}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		foreach (indices(G->G->commands), string n) if (n == name || has_prefix(n, name + "#")) m_delete(G->G->commands, n);
		if (!sizeof(active_channels)) G->G->commands[name] = check_perms;
		else foreach (active_channels, string chan) if (chan!="") G->G->commands[name + "#" + chan] = check_perms;
	}
}

//A command handler could be a string (echo that string), an array of strings (echo
//them all, in order), or a function returning one of the above. Note that an array
//of functions is NOT permitted, nor arrays of arrays.
typedef function|string|array(string) command_handler;

//Attempt to find a "likely command" for a given channel.
//If it returns 0, there's no such command. It may return a function
//that eventually fails, but it will attempt to do so as rarely as
//possible; returning nonzero will NORMALLY mean that the command is
//fully active.
command_handler find_command(object channel, string cmd, int is_mod)
{
	//Prevent commands from containing a hash, allowing us to use that for
	//per-chan commands. Since channel->name begins with a hash, that's our
	//separator. We'll try "help#rosuav" and "help" for "!help".
	if (has_value(cmd, '#')) return 0;
	foreach (({cmd + channel->name, cmd}), string tryme)
	{
		//NOTE: G->G->commands holds the actual function that gets
		//called, but we need the corresponding object.
		function f = G->G->commands[tryme];
		if (f)
		{
			object obj = function_object(f);
			if (!obj->all_channels && !channel->config->allcmds) continue;
			if (obj->require_moderator && !is_mod) continue;
			//If we get here, the command is acceptable.
			return f;
		}
		if (string|array(string) response = G->G->echocommands[tryme]) return response;
	}
}

string describe_time_short(int tm)
{
	string msg = "";
	int secs = tm;
	if (int t = secs/86400) {msg += sprintf("%d, ", t); secs %= 86400;}
	if (tm >= 3600) msg += sprintf("%02d:%02d:%02d", secs/3600, (secs%3600)/60, secs%60);
	else if (tm >= 60) msg += sprintf("%02d:%02d", secs/60, secs%60);
	else msg += sprintf("%02d", tm);
	return msg;
}

string describe_time(int tm)
{
	string msg = "";
	if (int t = tm/86400) {msg += sprintf(", %d day%s", t, t>1?"s":""); tm %= 86400;}
	if (int t = tm/3600) {msg += sprintf(", %d hour%s", t, t>1?"s":""); tm %= 3600;}
	if (int t = tm/60) {msg += sprintf(", %d minute%s", t, t>1?"s":""); tm %= 60;}
	if (tm) msg += sprintf(", %d second%s", tm, tm>1?"s":"");
	return msg[2..];
}

string channel_uptime(string channel)
{
	if (object started = G->G->stream_online_since[channel])
		return describe_time(started->distance(Calendar.now())->how_many(Calendar.Second()));
}

int invoke_browser(string url)
{
	if (G->G->invoke_cmd) {Process.create_process(G->G->invoke_cmd+({url})); return 1;}
	foreach (({
		#ifdef __NT__
		//Windows
		({"cmd","/c","start"}),
		#elif defined(__APPLE__)
		//Darwin
		({"open"}),
		#else
		//Linux, various. Try the first one in the list; if it doesn't
		//work, go on to the next, and the next. A sloppy technique. :(
		({"xdg-open"}),
		({"exo-open"}),
		({"gnome-open"}),
		({"kde-open"}),
		#endif
	}),array(string) cmd) catch
	{
		Process.create_process(cmd+({url}));
		G->G->invoke_cmd = cmd; //Remember this for next time, to save a bit of trouble
		return 1; //If no exception is thrown, hope that it worked.
	};
}

mapping G_G_(string ... path)
{
	mapping ret = G->G;
	foreach (path, string part)
	{
		if (!ret[part]) ret[part] = ([]);
		ret = ret[part];
	}
	return ret;
}

void register_hook(string event, function handler)
{
	string origin = Program.defined(function_program(handler));
	//Trim out any hooks for this event that were defined in the same class
	//"Same class" is identified by its textual origin, rather than the actual
	//identity of the program, such that a reloaded/updated version of a class
	//counts as the same one as before.
	G->G->hooks[event] = filter(G->G->hooks[event] || ({ }),
		lambda(array(string|function) f) {return f[0] != origin;}
	) + ({({origin, handler})});
}

int runhooks(string event, string skip, mixed ... args)
{
	array(array(string|function)) hooks = G->G->hooks[event];
	if (!hooks) return 0; //Nothing registered for this event
	foreach (hooks, [string name, function func]) if (!skip || skip<name)
		if (mixed ex = catch {if (func(@args)) return 1;})
			werror("Error in hook %s->%s: %s", name, event, describe_backtrace(ex));
}
