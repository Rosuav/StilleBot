void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->bouncers) G->G->bouncers = ([]);
	if (!G->G->http_endpoints) G->G->http_endpoints = ([]);
	if (!G->G->http_sessions) G->G->http_sessions = ([]);
}

//A sendable message could be a string (echo that string), a mapping with a "message"
//key (echo that string, possibly with other attributes), or an array of the above
//(echo them all, in order). An array of arrays is NOT permitted - this does not nest.
typedef string|mapping|array(string|mapping) echoable_message;
typedef echoable_message|function(object,object,string:echoable_message) command_handler;

class command
{
	constant all_channels = 0; //Set to 1 if this command should be available even if allcmds is not set for the channel
	constant require_moderator = 0; //Set to 1 if the command is mods-only
	constant active_channels = ({ }); //To restrict this to some channels only, set this to a non-empty array.
	constant docstring = ""; //Override this with your docs
	//Override this to do the command's actual functionality, after permission checks.
	//Return a string to send that string, with "@$$" to @-notify the user.
	echoable_message process(object channel, object person, string param) { }

	//Make sure that inappropriate commands aren't called. Normally these
	//checks are done in find_command below, but it's cheap to re-check.
	//(Maybe remove this and depend on find_command??)
	echoable_message check_perms(object channel, object person, string param)
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
		//Update the docs for this command. NOTE: Nothing will currently
		//remove docs for a defunct command. Do this manually.
		if (sscanf(docstring, "%*[\n]%s\n\n%s", string summary, string main) && main)
		{
			string content = string_to_utf8(sprintf(#"# !%s: %s

Available to: %s

%s
", name, summary, require_moderator ? "mods only" : "all users", main));
			string fn = sprintf("commands/%s.md", name);
			string oldcontent = Stdio.read_file(fn);
			if (content != oldcontent) Stdio.write_file(fn, content);
			string oldindex = Stdio.read_file("commands/index.md");
			sscanf(oldindex, "%s\n\nCommands in alphabetical order:\n%s\n\n---\n%s",
				string before, string commands, string after);
			array cmds = commands / "\n* "; //First one will always be an empty string
			string newtext = sprintf("[!%s: %s](%[0]s)", name, summary);
			foreach (cmds; int i; string cmd)
			{
				if (has_prefix(cmd, sprintf("[!%s: ", name)))
				{
					cmds[i] = newtext;
					newtext = 0;
					break;
				}
			}
			if (newtext) cmds += ({newtext});
			sort(cmds); //TODO: Figure out why this didn't work
			string index = sprintf("%s\n\nCommands in alphabetical order:\n%s\n\n---\n%s",
				before, cmds * "\n* ", after);
			if (index != oldindex) Stdio.write_file("commands/index.md", index);
		}
	}
}

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
	if (has_value(cmd, '!')) return 0; //Pseudo-commands can't be run as normal commands
	cmd = lower_case(cmd); //TODO: Switch this out for a proper Unicode casefold
	foreach (({cmd + channel->name, cmd}), string tryme)
	{
		//NOTE: G->G->commands holds the actual function that gets
		//called, but we need the corresponding object.
		command_handler f = G->G->commands[tryme];
		if (f)
		{
			object obj = functionp(f) ? function_object(f) : ([]);
			if (!obj->all_channels && !channel->config->allcmds) continue;
			if (obj->require_moderator && !is_mod) continue;
			//If we get here, the command is acceptable.
			return f;
		}
		//Echo commands are not allowed to be functions, unsurprisingly
		if (echoable_message response = G->G->echocommands[tryme]) return response;
	}
}

//Shorthand for a common targeting style
echoable_message targeted(string text) {return (["message": text, "prefix": "@$$: "]);}

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

/* Easily slide a delayed callback to the latest code

In create(), call register_bouncer(some_function)
In some_function, start with:
if (function f = bounce(this_function)) return f(...my args...);

If the code has been updated since the callback was triggered, it'll give back
the new function. Functions are identified by their %O descriptions.
*/
void register_bouncer(function f)
{
	G->G->bouncers[sprintf("%O", f)] = f;
}
function|void bounce(function f)
{
	function current = G->G->bouncers[sprintf("%O", f)];
	if (current != f) return current;
	return UNDEFINED;
}

class http_endpoint
{
	//Set to an sscanf pattern to handle multiple request URIs. Otherwise will handle just "/myname".
	constant http_path_pattern = 0;
	//A channel will be provided if and only if this is chan_foo.pike and the URL is /channels/spam/foo
	mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object|void channel) { }

	void create(string name)
	{
		if (http_path_pattern)
		{
			G->G->http_endpoints[http_path_pattern] = http_request;
			return;
		}
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->http_endpoints[name] = http_request;
	}
}

mapping(string:mixed) render_template(string template, mapping(string:string) replacements)
{
	string content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template);
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template);
	for (int i = 1; i < sizeof(pieces); i += 2)
	{
		string token = pieces[i];
		if (token == "") {pieces[i] = "$$"; continue;} //Escape a $$ by doubling it ($$$$)
		if (sizeof(token) > 80 || has_value(token, ' ')) //TODO: Check more reliably for it being a 'token'
			error("Invalid token name %O in templates/%s - possible mismatched marker",
				"$$" + token[..80] + "$$", template);
		int trim_before = has_prefix(token, ">");
		int trim_after  = has_suffix(token, "<");
		token = token[trim_before..<trim_after];
		if (!replacements[token]) error("Token %O not found in templates/%s", "$$" + token + "$$", template);
		pieces[i] = replacements[token];
		if (pieces[i] == "")
		{
			if (trim_before) pieces[i-1] = String.trim("^" + pieces[i-1])[1..];
			if (trim_after)  pieces[i+1] = String.trim(pieces[i+1] + "$")[..<1];
		}
	}
	content = pieces * "";
	if (has_suffix(template, ".md")) return render_template("markdown.html", replacements | (["content": Tools.Markdown.parse(content)]));
	return ([
		"data": string_to_utf8(content),
		"type": "text/html; charset=\"UTF-8\"",
	]);
}

mapping(string:mixed) redirect(string url, int|void status)
{
	return (["error": status||302, "extra_heads": (["Location": url])]);
}

class TwitchAuth
{
	inherit Web.Auth.OAuth2.Client;
	constant OAUTH_AUTH_URI  = "https://id.twitch.tv/oauth2/authorize";
	constant OAUTH_TOKEN_URI = "https://id.twitch.tv/oauth2/token";
	protected multiset(string) valid_scopes = (<"user_read">); //TODO: Fill these in
}

void session_cleanup()
{
	//Go through all HTTP sessions and dispose of old ones
	mapping sess = G->G->http_sessions;
	int limit = time();
	foreach (sess; string cookie; mapping info)
		if (info->expires <= limit) m_delete(sess, cookie);
}

//Make sure we have a session and cookie active. The given response will have
//a Set-Cookie added if necessary, otherwise no changes are made.
void ensure_session(Protocols.HTTP.Server.Request req, mapping(string:mixed) resp)
{
	if (req->misc->session) return 0;
	string cookie;
	do {cookie = random(1<<64)->digits(36);} while (G->G->http_sessions[cookie]);
	req->misc->session = G->G->http_sessions[cookie] = (["expires": time() + 86400]);
	if (!resp->extra_heads) resp->extra_heads = ([]);
	resp->extra_heads["Set-Cookie"] = "session=" + cookie;
	call_out(session_cleanup, 86401); //TODO: Don't have too many of these queued.
}
