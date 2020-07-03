//TODO: Make globals not reference any globals other than persist_config/persist_status.
//Would mean we no longer need to worry about lingering state as much.

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
	if (!G->G->websocket_types) G->G->websocket_types = ([]);
	if (!G->G->websocket_groups) G->G->websocket_groups = ([]);
	if (!G->G->webhook_endpoints) G->G->webhook_endpoints = ([]); //Doesn't currently have a corresponding inheritable
}

//A sendable message could be a string (echo that string), a mapping with a "message"
//key (echo that string, possibly with other attributes), or an array of the above
//(echo them all, in order). Mappings and arrays can nest arbitrarily, but in practice,
//most commands stick to one of the following:
//- "single message"
//- ({"sequential", "messages"})
//- (["message": "text to send", "attr": "value"])
//- (["message": ({"sequential", "messages"}), "attr": "value"])
typedef string|mapping(string:string|_echoable_message)|array(_echoable_message) _echoable_message;
//To avoid recompilation ambiguities, the added constant is simply a reference to the
//(private) recursive typedef above.
typedef _echoable_message echoable_message;
typedef echoable_message|function(object,object,string:echoable_message) command_handler;

class command
{
	constant require_allcmds = 1; //Set to 0 if the command should be available even if allcmds is not set for the channel
	constant require_moderator = 0; //(deprecated) Set to 1 if the command is mods-only (equivalent to access="mod")
	//Command flags, same as can be managed for echocommands with !setcmd
	//Note that the keywords given here by default should be treated as equivalent
	//to a 0, as echocommands will normally use 0 for the defaults.
	constant access = "any"; //Set to "mod" for mod-only commands - others may be available later
	constant visibility = "visible"; //Set to "hidden" to suppress the command from !help (or set hidden_command to 1, deprecated alternative)
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
		if (require_allcmds && !channel->config->allcmds) return 0;
		if ((require_moderator || access == "mod") && !channel->mods[person->user]) return 0;
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
", name, summary, require_moderator ? "mods only" : (["mod": "mods only", "any": "all users"])[access], main));
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
		command_handler f = G->G->commands[tryme] || G->G->echocommands[tryme];
		if (!f) continue;
		object|mapping flags = functionp(f) ? function_object(f) : mappingp(f) ? f : ([]);
		if (flags->require_allcmds && !channel->config->allcmds) continue;
		if ((flags->require_moderator || flags->access == "mod") && !is_mod) continue;
		//If we get here, the command is acceptable.
		return f;
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

class websocket_handler
{
	mapping(string|int:array(object)) websocket_groups;
	//If msg->cmd is "init", it's a new client and base processing has already been done.
	//If msg is 0, a client has disconnected and is about to be removed from its group.
	//Use websocket_groups[conn->group] to find an array of related sockets.
	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) { }

	protected void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		if (!(websocket_groups = G->G->websocket_groups[name]))
			websocket_groups = G->G->websocket_groups[name] = ([]);
		G->G->websocket_types[name] = this;
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

#if constant(Parser.Markdown)
class Renderer
{
	inherit Parser.Markdown.Renderer;
	//Put borders on all tables
	string table(string header, string body, mapping token)
	{
		return ::table(header, body, (["attr_border": "1"]) | token);
	}
	//Allow cell spanning by putting just a hyphen in a cell (it will
	//be joined to the NEXT cell, not the preceding one)
	int spancount = 0;
	string tablerow(string row, mapping token)
	{
		spancount = 0; //Can't span across rows
		if (row == "") return ""; //Suppress the entire row if all cells were suppressed
		return ::tablerow(row, token);
	}
	string tablecell(string cell, mapping flags, mapping token)
	{
		if (String.trim(cell) == "-") {++spancount; return "";} //A cell with just a hyphen will not be rendered, and the next cell spans.
		if (spancount) token |= (["attr_colspan": (string)(spancount + 1)]);
		spancount = 0;
		return ::tablecell(cell, flags, token);
	}
	//Interpolate magic markers
	string text(string t)
	{
		if (!options->user_text) return t;
		array texts = options->user_text->texts;
		string output = "";
		while (sscanf(t, "%s\uFFFA%d\uFFFB%s", string before, int idx, string after))
		{
			output += before + replace(texts[idx], (["<": "&lt;", "&": "&amp;"]));
			t = after;
		}
		return output + t;
	}
	//Allow a blockquote to become a dialog
	string blockquote(string text, mapping token)
	{
		if (string tag = m_delete(token, "attr_tag"))
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token), text);
		return ::blockquote(text, token);
	}
	string heading(string text, int level, string raw, mapping token)
	{
		if (options->headings && !options->headings[level])
			//Retain the first-seen heading of each level
			options->headings[level] = text;
		return ::heading(text, level, raw, token);
	}
}
class Lexer
{
	inherit Parser.Markdown.Lexer;
	bool parse_attrs(string text, mapping tok)
	{
		if (sscanf(text, "{:%[^{}\n]}%s", string attrs, string empty) && empty == "")
		{
			foreach (attrs / " ", string att)
			{
				if (sscanf(att, ".%s", string cls) && cls && cls != "")
				{
					if (tok["attr_class"]) tok["attr_class"] += " " + cls;
					else tok["attr_class"] = cls;
				}
				else if (sscanf(att, "#%s", string id) && id && id != "")
					tok["attr_id"] = id;
				else if (sscanf(att, "%s=%s", string a, string v) && a != "" && v)
					tok["attr_" + a] = v;
			}
			return 1;
		}
	}
	object_program lex(string src)
	{
		::lex(src);
		foreach (tokens; int i; mapping tok)
		{
			if (tok->type == "paragraph" && tok->text[-1] == '}')
			{
				mapping target = tok;
				array(string) lines = tok->text / "\n";
				if (tokens[i + 1]->type == "blockquote_end") target = tokens[i + 1];
				else if (sizeof(lines) == 1 && i > 0)
				{
					//It's a paragraph consisting ONLY of attributes.
					//Attach the attributes to the preceding token.
					//TODO: Only do this if the preceding token is a
					//type that can take attributes.
					target = tokens[i - 1];
				}
				if (parse_attrs(lines[-1], target))
				{
					if (sizeof(lines) > 1) tok->text = lines[..<1] * "\n";
					else tok->type = "space"; //Suppress the text altogether.
				}
			}
			if (tok->type == "list_end")
			{
				//Scan backwards into the list, finding the last text.
				//If that text can be parsed as attributes, apply them to the
				//list_end, which will then apply them to the list itself.
				for (int j = i - 1; j >= 0; --j)
				{
					if (tokens[j]->type == "text")
					{
						if (parse_attrs(tokens[j]->text, tok))
							tokens[j]->type = "space";
						break;
					}
					if (!(<"space", "list_item_end">)[tokens[j]->type]) break;
				}
			}
		}
		return this;
	}
}

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
		if (sizeof(token) > 200) //TODO: Check more reliably for it being a 'token'
			error("Invalid token name %O in templates/%s - possible mismatched marker\n",
				"$$" + token[..80] + "$$", template);
		sscanf(token, "%s||%s", token, string dflt);
		int trim_before = has_prefix(token, ">");
		int trim_after  = has_suffix(token, "<");
		token = token[trim_before..<trim_after];
		if (!replacements[token])
		{
			if (dflt) pieces[i] = dflt;
			else error("Token %O not found in templates/%s\n", "$$" + token + "$$", template);
		}
		else pieces[i] = replacements[token];
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
			"renderer": Renderer, "lexer": Lexer,
			"user_text": replacements["user text"],
			"headings": headings,
			"attributes": 1, //Ignored if using older Pike (or, as of 2020-04-13, vanilla Pike - it's only on branch rosuav/markdown-attribute-syntax)
		]));
		return render_template("markdown.html", ([
			//Defaults - can be overridden
			"title": headings[1] || "StilleBot",
			"backlink": replacements->channel && "<small><a href=\"./\">StilleBot - " + replacements->channel + "</a></small>",
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
#else
//With no Markdown parser, the web interface will be broken, but the rest of the bot should be fine.
mapping(string:mixed) render_template(string template, mapping(string:string) replacements)
{
	return (["data": "ERROR: Markdown parser unavailable", "type": "text/plain"]);
}
#endif

mapping(string:mixed) redirect(string url, int|void status)
{
	return (["error": status||302, "extra_heads": (["Location": url])]);
}

class TwitchAuth
{
	inherit Web.Auth.OAuth2.Client;
	constant OAUTH_AUTH_URI  = "https://id.twitch.tv/oauth2/authorize";
	constant OAUTH_TOKEN_URI = "https://id.twitch.tv/oauth2/token";
	protected multiset(string) valid_scopes = (<
		//Helix API:
		"analytics:read:extensions", "analytics:read:games", "bits:read",
		"channel:edit:commercial", "channel:read:subscriptions", "clips:edit",
		"user:edit", "user:edit:broadcast", "user:edit:follows",
		"user:read:broadcast", "user:read:email",
		//v5 API
		"channel_check_subscription", "channel_commercial", "channel_editor",
		"channel_feed_edit", "channel_feed_read", "channel_read", "channel_stream",
		"channel_subscriptions", "chat_login", "collections_edit", "communities_edit",
		"comunities_moderate", "openid", "user_blocks_edit", "user_blocks_read",
		"user_read", "user_subscriptions", "viewing_activity_read",
		//Chat/PubSub
		"channel:moderate", "chat:read", "chat:edit", "whispers:read", "whispers:edit",
		//Hype trains (new as of 20200619)
		"channel:read:hype_train",
		//Insufficiently documented. Dunno if we need it or not.
		"moderation:read",
	>);
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
	resp->extra_heads["Set-Cookie"] = "session=" + cookie + "; Path=/";
	call_out(session_cleanup, 86401); //TODO: Don't have too many of these queued.
}

mapping(string:mixed)|Concurrent.Future twitchlogin(Protocols.HTTP.Server.Request req, multiset(string) scopes, string|void next)
{
	mapping cfg = persist_config["ircsettings"];
	object auth = TwitchAuth(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", scopes);
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		//write("%O\n", req->variables);
		auth->set_from_cookie(auth->request_access_token(req->variables->code));
		return Protocols.HTTP.Promise.get_url("https://api.twitch.tv/helix/users",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + auth->access_token,
				"Client-ID": cfg->clientid,
			])])))->then(lambda(Protocols.HTTP.Promise.Result res)
		{
			mapping user = Standards.JSON.decode_utf8(res->get())->data[0];
			//write("Login: %O %O\n", auth->access_token, user);
			string dest = m_delete(req->misc->session, "redirect_after_login");
			if (!dest || dest == req->not_query || has_prefix(req->not_query, dest + "?"))
			{
				//If no destination was given, try to figure out a plausible default.
				//For streamers, redirect to the stream's landing page. Doesn't work
				//for mods, as we have no easy way to check which channel(s).
				object channel = G->G->irc->channels["#" + user->login];
				if (channel && channel->config->allcmds)
					dest = "/channels/" + user->login + "/";
				else dest = "/login_ok";
			}
			mapping resp = redirect(dest);
			ensure_session(req, resp);
			req->misc->session->user = user;
			req->misc->session->scopes = (multiset)(req->variables->scope / " ");
			req->misc->session->token = auth->access_token;
			return resp;
		});
	}
	//write("Redirecting to Twitch...\n%s\n", auth->get_auth_uri());
	mapping resp = redirect(auth->get_auth_uri());
	ensure_session(req, resp);
	req->misc->session->redirect_after_login = next || req->full_query;
	return resp;
}

//Make sure we have a logged-in user. Returns 0 if the user is already logged in, or
//a response that should be sent before continuing.
//if (mapping resp = ensure_login(req)) return resp;
//Provide a space-separated list of scopes to also ensure that these scopes are active.
mapping(string:mixed) ensure_login(Protocols.HTTP.Server.Request req, string|void scopes)
{
	multiset havescopes = req->misc->session->?scopes;
	multiset wantscopes = scopes ? (multiset)(scopes / " ") : (<>);
	wantscopes[""] = 0; //Remove any empty entry, just in case
	if (!havescopes) return twitchlogin(req, wantscopes); //Even if you aren't requesting any scopes
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	if (sizeof(needscopes) > sizeof(havescopes)) return twitchlogin(req, needscopes);
	//If we get here, it's all good, carry on.
}

//User text will be given to the given user_text object; emotes will be markdowned.
string emotify_user_text(string text, object user)
{
	mapping emotes = G->G->emote_code_to_markdown;
	if (!emotes) return user(text);
	array words = text / " ";
	//This is pretty inefficient - it makes a separate user() entry for each
	//individual word. If this is a problem, consider at least checking for
	//any emotes at all, and if not, just return user(text) instead.
	foreach (words; int i; string w)
		words[i] = emotes[w] || user(w);
	return words * " ";
}
