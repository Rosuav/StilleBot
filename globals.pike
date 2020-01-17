protected void create(string n)
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
//(echo them all, in order).
//Note that (["message": ({...})]) is valid, but the meaningful attributes may not be
//the same as for a string message. Note also that, in theory, mappings and arrays can
//nest arbitrarily, but in practice, stick to one of the following:
//- "single message"
//- ({"sequential", "messages"})
//- (["message": "text to send", "attr": "value"])
//- ({(["message": "sequential", "attr": "value"]), "messages"})
//- (["message": ({"sequential", "messages"}), "attr": "value"])
//- ([({(["message": "sequential", "attr": "value"]), "messages"}), "otherattr": "value"])
//Don't nest more deeply than these.
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
	protected void create(string name)
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
	mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, object|void channel) { }

	protected void create(string name)
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

class user_text
{
	/* Instantiate one of these, then call it with any user-defined text
	(untrusted text) to be inserted into the output. Render whatever it
	gives back. Then, provide this as the "user text" option (yes, with
	the space) to render_template, and the texts will be safely inserted
	into the resulting output file. */
	array texts = ({ });
	protected string `()(string text)
	{
		texts += ({text});
		return sprintf("\uFFFA%d\uFFFB", sizeof(texts) - 1);
	}
}

class _Markdown
{
	//We can't just inherit Tools.Markdown.Renderer as it's protected
	//(or at least, it is in 8.1 as of 20190201). So we inherit the
	//entire module and make our own small tweaks.
	inherit Tools.Markdown;
	class AltRenderer
	{
		inherit Renderer;
		//Put borders on all tables
		string table(string header, string body)
		{
			return replace(::table(header, body), "<table>", "<table border>");
		}
		//Allow cell spanning by putting just a hyphen in a cell (it will
		//be joined to the NEXT cell, not the preceding one)
		int spancount = 0;
		string tablerow(string row)
		{
			spancount = 0; //Can't span across rows
			if (row == "") return ""; //Suppress the entire row if all cells were suppressed
			return ::tablerow(row);
		}
		string tablecell(string cell, mapping flags)
		{
			if (String.trim(cell) == "-") {++spancount; return "";} //A cell with just a hyphen will not be rendered, and the next cell spans.
			string html = ::tablecell(cell, flags);
			if (!spancount) return html;
			string colspan = " colspan=" + (spancount + 1);
			spancount = 0;
			//Insert the colspan just before the first ">"
			array parts = html / ">";
			parts[0] += colspan;
			return parts * ">";
		}
		//Interpolate magic markers
		string text(string t)
		{
			if (!options->user_text) return t;
			array texts = options->user_text->texts;
			string output = "";
			while (sscanf(t, "%s\uFFFA%d\uFFFB%s", string before, int idx, string after))
			{
				output += before + encode_html(texts[idx]);
				t = after;
			}
			return output + t;
		}
		//Allow a blockquote to become a dialog
		string blockquote(string text)
		{
			if (sscanf(text, "<p>dialog%[^\n<]</p>%s", string attr, string t) && t)
			{
				//It's a block quote that starts "> dialog" or "> dialog x=y a=b"
				//Turn it into a <dialog> tag instead of <blockquote>.
				return sprintf("<dialog%s>%s</dialog>", attr, t);
			}
			return sprintf("<blockquote>%s</blockquote>", text);
		}
		//Allow paragraphs to get extra attributes
		string paragraph(string text)
		{
			string last_line = (text / "\n")[-1];
			mapping attr = ([]);
			if (sscanf(last_line, "{:%{ %[.#]%[a-z]%}}%s", array attrs, string empty) && empty == "")
			{
				text = text[..<sizeof(last_line)+1];
				foreach (attrs, [string t, string val]) switch (t)
				{
					case ".":
						if (attr["class"]) attr["class"] += " " + val;
						else attr["class"] = val;
						break;
					case "#": attr["id"] = val; break;
					default: break; //Shouldn't happen
				}
			}
			return sprintf("<p%{ %s=%q%}>%s</p>", (array)attr, text);
		}
		//Retain headings in case they're wanted
		string heading(string text, int level, string raw)
		{
			if (options->headings && !options->headings[level])
				//Retain the first-seen heading of each level
				options->headings[level] = text;
			return ::heading(text, level, raw);
		}
	}
}
program _AltRenderer = _Markdown()->AltRenderer;

mapping(string:mixed) render_template(string template, mapping(string:string) replacements)
{
	string content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template + "\n");
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template + "\n");
	for (int i = 1; i < sizeof(pieces); i += 2)
	{
		string token = pieces[i];
		if (token == "") {pieces[i] = "$$"; continue;} //Escape a $$ by doubling it ($$$$)
		if (sizeof(token) > 80 || has_value(token, ' ')) //TODO: Check more reliably for it being a 'token'
			error("Invalid token name %O in templates/%s - possible mismatched marker\n",
				"$$" + token[..80] + "$$", template);
		int trim_before = has_prefix(token, ">");
		int trim_after  = has_suffix(token, "<");
		token = token[trim_before..<trim_after];
		if (!replacements[token]) error("Token %O not found in templates/%s\n", "$$" + token + "$$", template);
		pieces[i] = replacements[token];
		if (pieces[i] == "")
		{
			if (trim_before) pieces[i-1] = String.trim("^" + pieces[i-1])[1..];
			if (trim_after)  pieces[i+1] = String.trim(pieces[i+1] + "$")[..<1];
		}
	}
	content = pieces * "";
	if (has_suffix(template, ".md"))
	{
		mapping headings = ([]);
		string content = Tools.Markdown.parse(content, ([
			"renderer": _AltRenderer,
			"user_text": replacements["user text"],
			"headings": headings,
		]));
		return render_template("markdown.html", ([
			//Defaults - can be overridden
			"title": headings[1] || "StilleBot",
			"backlink": "<small><a href=\"./\">StilleBot - " + replacements->channel + "</a></small>",
		]) | replacements | ([
			//Forced attributes
			"content": content,
		]));
	}
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
	req->misc->session = G->G->http_sessions[cookie] = (["cookie": cookie, "expires": time() + 86400]);
	if (!resp->extra_heads) resp->extra_heads = ([]);
	resp->extra_heads["Set-Cookie"] = "session=" + cookie;
	call_out(session_cleanup, 86401); //TODO: Don't have too many of these queued.
}
