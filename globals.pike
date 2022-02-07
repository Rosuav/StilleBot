//TODO: Make globals not reference any globals other than persist_config/persist_status.
//Would mean we no longer need to worry about lingering state as much.

protected void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl)
			if (!G->G[gl]) G->G[gl] = ([]);
	if (!all_constants()["create_hook"]) add_constant("create_hook", _HookID("")); //Don't recreate this one
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

constant _COMMAND_DOCS = #"# !%s: %s

Available to: %s
%s
%s
";

@"G->G->commands";
class command
{
	constant require_moderator = 0; //(deprecated) Set to 1 if the command is mods-only (equivalent to access="mod")
	//Command flags, same as can be managed for echocommands with !setcmd
	//Note that the keywords given here by default should be treated as equivalent
	//to a 0, as echocommands will normally use 0 for the defaults.
	constant access = "any"; //Set to "mod" for mod-only, "vip" for VIPs and mods, or "none" for disabled/internal-only commands (more useful for echo commands)
	constant visibility = "visible"; //Set to "hidden" to suppress the command from !help (or set hidden_command to 1, deprecated alternative)
	constant featurename = "allcmds"; //Set to a feature flag to allow this command to be governed by !features (not usually appropriate for echocommands)
	constant active_channels = ({ }); //To restrict this to some channels only, set this to a non-empty array.
	constant docstring = ""; //Override this with your docs
	//Override this to do the command's actual functionality, after permission checks.
	//Return a string to send that string, with "@$$" to @-notify the user.
	echoable_message process(object channel, mapping person, string param) { }

	//Make sure that inappropriate commands aren't called. Normally these
	//checks are done in find_command below, but it's cheap to re-check.
	//(Maybe remove this and depend on find_command??) EXCEPTION: VIPs are
	//not recognized by find_command currently, so non-VIPs will see those
	//commands, and they'll get caught here. This makes !help less helpful.
	echoable_message check_perms(object channel, mapping person, string param)
	{
		if (featurename && (channel->config->features[?featurename] || channel->config->allcmds) <= 0) return 0;
		if ((require_moderator || access == "mod") && !channel->mods[person->user]) return 0;
		if (access == "vip" && !channel->mods[person->user] && !person->badges->?vip) return 0;
		if (access == "none") return 0;
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
			string content = string_to_utf8(sprintf(_COMMAND_DOCS, name, summary,
				require_moderator ? "mods only" : (["mod": "mods only", "vip": "mods/VIPs", "any": "all users", "none": "nobody (internal only)"])[access],
				featurename && featurename != "allcmds" ? "\nPart of manageable feature: " + featurename + "\n" : "", //TODO: Grab the description from modules/features.pike?
				main));
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
		if (flags->featurename && (channel->config->features[?flags->featurename] || channel->config->allcmds) <= 0) continue;
		if ((flags->require_moderator || flags->access == "mod") && !is_mod) continue;
		//Note that VIP commands aren't filtered here, so non-VIPs might see them. They'll be blocked by check_perms.
		if (flags->access == "none") continue;
		//If we get here, the command is acceptable.
		return f;
	}
}

//Shorthand for a common targeting style
echoable_message targeted(string text) {return (["message": text, "prefix": "@$$: "]);}

//Return a Second or a Fraction representing the given ISO time, or 0 if unparseable
Calendar.ISO.Second time_from_iso(string time) {
	if (object ts = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", time)) return ts;
	return Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s.%f%z", time);
}

void _unhandled_error(mixed err) {
	werror("Unhandled asynchronous exception\n%s\n", describe_backtrace(err));
}
void _ignore_result(mixed value) { }

//TODO: Replace this with a Function.function_type() check or similar
int(0..1) is_genstate(mixed x) {return functionp(x) && has_value(sprintf("%O", x), "\\u0000");}

//Handle asynchronous results. Will either call the callback immediately
//(before returning), or will call it when the asynchronous results are
//made available. Result and error callbacks get called with value and
//any extra args appended.
//TODO: If/when a Pike function is available to unambiguously identify
//whether a generator has finished or not, permit more types of yields:
//1) Concurrent.Future, as now
//2) Generator state function
//3) Array of the above. Use Concurrent.all implicitly, and return an array.
//4) Anything else?
class spawn_task(mixed gen, function|void got_result, function|void got_error) {
	mixed extra;
	protected void create(mixed ... args) {
		extra = args;
		if (!got_result) got_result = _ignore_result;
		if (!got_error) got_error = _unhandled_error;
		if (is_genstate(gen)) pump(0, 0);
		else if (objectp(gen) && gen->then)
			gen->then(got_result, got_error, @extra);
		else got_result(gen, @extra);
	}
	//Pump a generator function. It should yield Futures until it returns a
	//final result. If it yields a non-Future, it will be passed back
	//immediately, but don't do that.
	void pump(mixed last, mixed err) {
		mixed resp;
		if (mixed ex = catch {resp = gen(last){if (err) throw(err);};}) {got_error(ex, @extra); return;}
		if (undefinedp(resp)) got_result(last, @extra);
		else if (is_genstate(resp)) spawn_task(resp, pump, propagate_error);
		else if (objectp(resp) && resp->then) resp->then(pump, propagate_error);
		else pump(resp, 0);
	}
	void propagate_error(mixed err) {pump(0, err || ({"Null error\n", backtrace()}));}
}
constant handle_async = spawn_task; //Compatibility name (deprecated)

//If cb is a spawn_task->pump/propagate_error function, return the corresponding task, else 0.
mixed find_callback_task(function cb) {
	object obj = function_object(cb);
	//Note: Don't check if the program is exactly spawn_task from above, since code
	//might have been reloaded. This should be able to recognize older-instance tasks.
	if (function_name(object_program(obj)) == "spawn_task") return obj;
}

//mixed _ = yield(task_sleep(seconds)); //Delay the current task efficiently
class task_sleep(int|float delay) {
	void then(function whendone) {
		call_out(whendone, delay, delay || "0"); //Never yield zero, it can cause confusion
	}
}

//Some commands are available for echocommands to call on.
@"G->G->builtins";
class builtin_command {
	inherit command;
	constant command_description = "Duplicate, replace, or adjust the normal handling of the !<> command";
	constant builtin_description = ""; //If omitted, uses command_description
	constant builtin_name = ""; //Short human-readable name for the drop-down
	constant builtin_param = ""; //Label for the parameter, or "/Label/option/option/option" to offer specific selections. If blank, has no parameter.
	constant default_response = ""; //The response to the default command, and also the default suggestion
	constant vars_provided = ([ ]); //List all available vars (it's okay if they aren't all always provided)
	constant aliases = ({ }); //Add aliases here and they'll be defaultly aliased if shadowed too
	constant command_suggestions = 0; //If unset, will use builtin_name and default_response
	//Override this either as-is or as a continue function to return the useful params.
	//Note that the person mapping may be as skeletal as (["user": "Nobody"]) - all
	//other keys are optional.
	mapping|function|Concurrent.Future message_params(object channel, mapping person, string param) { }

	protected void create(string name)
	{
		::create(name);
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->builtins[name] = this;
		foreach (aliases, string alias) G->G->commands[alias] = check_perms;
		if (default_response == "") m_delete(G->G->commands, name); //Builtins with no default response shouldn't show up in a search
	}
	echoable_message process(object channel, mapping person, string param) {
		return default_response != "" && (["builtin": this, "builtin_param": param, "message": default_response]);
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

int channel_uptime(string channel)
{
	if (object started = G->G->stream_online_since[channel])
		return started->distance(Calendar.now())->how_many(Calendar.Second());
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

class _HookID(string event) {constant is_hook_annotation = 1;}

@"G->G->eventhooks"; //Unfortunate naming, since eventhook_types is completely different. Maybe when G->G->hooks is removed, rename this to that??
class hook {
	protected void create(string name) {
		//1) Clear out any hooks for the same name
		foreach (G->G->eventhooks;; mapping hooks) m_delete(hooks, name);
		//2) Go through all annotations in this and add hooks as appropriate
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (objectp(anno) && anno->is_hook_annotation) {
					if (anno->event == "") {//Create or replace a hook definition
						if (!G->G->eventhooks[key]) {
							add_constant("hook_" + key, _HookID(key));
							G->G->eventhooks[key] = ([]);
							//NOTE: The object annotated (available as this[key]) is
							//not currently used in any way. At some point I'll figure
							//out what's needed, and give it meaning, but until then,
							//be prepared to rewrite any hook provider objects.
						}
						continue;
					}
					//Otherwise, it's registering a function for an existing hook.
					if (!G->G->eventhooks[anno->event]) error("Unrecognized hook %s\n", anno->event);
					G->G->eventhooks[anno->event][name] = this[key];
				}
			}
		}
	}

	//Run all registered hook functions for the given event, in an arbitrary order
	//Unlike hooks set up with the register_hook/runhooks globals, there is no concept
	//of returning 1 to cancel the event, nor of deferring execution of the underlying
	//action. Event notifications are fire-and-forget.
	void event_notify(string event, mixed ... args) {
		mapping hooks = G->G->eventhooks[event];
		if (!hooks) error("Unrecognized hook %s\n", event);
		foreach (hooks; string name; function func)
			if (mixed ex = catch (func(@args)))
				werror("Error in hook %s->%s: %s", name, event, describe_backtrace(ex));
	}
}

//Deprecated way of implementing hooks. Is buggy in a number of ways. Use "inherit hook" instead (see above).
//To deregister a hook: register_hook("...event...", Program.defined(this_program));
@"G->G->hooks";
void register_hook(string event, function|string handler)
{
	string origin = functionp(handler) ? Program.defined(function_program(handler)) : handler;
	//Trim out any hooks for this event that were defined in the same class
	//"Same class" is identified by its textual origin, rather than the actual
	//identity of the program, such that a reloaded/updated version of a class
	//counts as the same one as before.
	G->G->hooks[event] = filter(G->G->hooks[event] || ({ }),
		lambda(array(string|function) f) {return f[0] != origin;}
	) + ({({origin, handler})}) * functionp(handler);
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
@"G->G->bouncers";
void register_bouncer(function f) {G->G->bouncers[sprintf("%O", f)] = f;}
function|void bounce(function f)
{
	function current = G->G->bouncers[sprintf("%O", f)];
	if (current != f) return current;
	return UNDEFINED;
}

@"G->G->enableable_modules";
class enableable_module {
	constant ENABLEABLE_FEATURES = ([]); //Map keywords to mappings containing descriptions and other info
	void enable_feature(object channel, string kwd, int state) { } //Enable/disable the given feature or reset it to default
	int can_manage_feature(object channel, string kwd) {return 1;} //Optional UI courtesy: Return 1 if can be activated, 2 if can be deactivated, 3 if both

	protected void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->enableable_modules[name] = this;
	}
}

@"G->G->http_endpoints";
class http_endpoint
{
	//Set to an sscanf pattern to handle multiple request URIs. Otherwise will handle just "/myname".
	constant http_path_pattern = 0;
	//A channel will be provided if and only if this is chan_foo.pike and the URL is /channels/spam/foo
	//May be a continue function or may return a Future. May also return a string (recommended for
	//debugging only, as it'll be an ugly text/plain document).
	mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) { }
	//Whitelist query variables for redirects. Three options: 0 means error, don't allow the
	//redirect at all; ([]) to allow redirect but suppress query vars; or vars&(<"...","...">)
	//to filter the variables to a specific set of keys.
	mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars) {return ([]);}

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

array(function|array) find_http_handler(string not_query) {
	//Simple lookups are like http_endpoints["listrewards"], without the slash.
	//Exclude eg http_endpoints["chan_vlc"] which are handled elsewhere.
	if (function handler = !has_prefix(not_query, "/chan_") && G->G->http_endpoints[not_query[1..]])
		return ({handler, ({ })});
	//Try all the sscanf-based handlers, eg http_endpoints["/channels/%[^/]/%[^/]"], with the slash
	//TODO: Look these up more efficiently (and deterministically)
	foreach (G->G->http_endpoints; string pat; function handler) if (has_prefix(pat, "/"))
	{
		//Match against an sscanf pattern, and require that the entire
		//string be consumed. If there's any left (the last piece is
		//non-empty), it's not a match - look for a deeper pattern.
		array pieces = array_sscanf(not_query, pat + "%s");
		if (pieces && sizeof(pieces) && pieces[-1] == "") return ({handler, pieces[..<1]});
	}
	return ({0, ({ })});
}

@"G->G->websocket_types"; @"G->G->websocket_groups";
class websocket_handler
{
	mapping(string|int:array(object)) websocket_groups;

	//Generate a state mapping for a particular connection group. If state is 0, no
	//information is sent; otherwise it must be a JSON-compatible mapping. An ID will
	//be given if update_one was called, otherwise it will be 0.
	mapping|Concurrent.Future get_state(string|int group, string|void id) { }

	//Override to validate any init requests. Return 0 to allow the socket
	//establishment, or an error message.
	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) { }

	//If msg->cmd is "init", it's a new client and base processing has already been done.
	//If msg is 0, a client has disconnected and is about to be removed from its group.
	//Use websocket_groups[conn->group] to find an array of related sockets.
	//Note that clients are all disconnected when code gets updated. Theoretically this
	//isn't necessary, but whatevs. The clients have to cope with reconnection logic for
	//other reasons anyway, so this should be smooth. Override this for full control, or
	//override it and call parent to augment.
	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (!msg) return;
		if (msg->cmd == "refresh" || msg->cmd == "init") send_update(conn);
		if (function f = this["websocket_cmd_" + msg->cmd]) f(conn, msg);
	}

	void _send_updates(array(object) socks, string|int group, mapping|void data) {
		spawn_task(data || get_state(group), _low_send_updates, 0, socks);
	}
	void _low_send_updates(mapping resp, array(object) socks) {
		if (!resp) return;
		resp->cmd = "update";
		foreach (socks, object sock)
			if (sock && sock->state == 1) sock->send_text(Standards.JSON.encode(resp));
	}

	//Send an update to a specific connection. If not provided, data will
	//be generated by get_state().
	void send_update(mapping(string:mixed) conn, mapping|void data) {
		_send_updates(({conn->sock}), conn->group, data);
	}

	//Update all connections in a given group.
	//Generates just one state object and sends it everywhere.
	void send_updates_all(string|int group, mapping|void data) {
		array dest = websocket_groups[group];
		if (dest && sizeof(dest)) _send_updates(dest, group, data);
	}

	void update_one(string|int group, string id) {send_updates_all(group, (["id": id, "data": get_state(group, id)]));}

	//Returns ({channel, subgroup}) - if channel is 0, it's not valid
	array(object|string) split_channel(string|void group) {
		if (!stringp(group) || !has_value(group, '#')) return ({0, ""}); //Including if we don't have a group set yet
		sscanf(group, "%s#%s", string subgroup, string chan);
		object channel = G->G->irc->channels["#" + chan];
		return ({channel, subgroup});
	}

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
		return sprintf("\uFFFAu%d\uFFFB", sizeof(texts) - 1);
	}
}

#if constant(Parser.Markdown)
bool _parse_attrs(string text, mapping tok) //Used in renderer and lexer - ideally would be just lexer, but whatevs
{
	if (sscanf(text, "{:%[^{}\n]}%s", string attrs, string empty) && empty == "")
	{
		attrs = String.trim(attrs);
		while (attrs != "") {
			sscanf(attrs, "%[^= ]%s", string att, attrs);
			if (att == "") {sscanf(attrs, "%*[= ]%s", attrs); continue;} //Malformed, ignore
			if (att[0] == '.') {
				if (tok["attr_class"]) tok["attr_class"] += " " + att[1..];
				else tok["attr_class"] = att[1..];
			}
			else if (att[0] == '#')
				tok["attr_id"] = att[1..];
			//Note that the more intuitive notation asdf="qwer zxcv" is NOT supported, as it
			//conflicts with Markdown's protections. So we use a weird at-quoting notation
			//instead. (Think "AT"-tribute? I dunno.)
			else if (sscanf(attrs, "=@%s@%*[ ]%s", string val, attrs) //Quoted value asdf=@qwer zxcv@
					|| sscanf(attrs, "=%s%*[ ]%s", val, attrs)) //Unquoted value asdf=qwer
				tok["attr_" + att] = val;
			else if (sscanf(attrs, "%*[ ]%s", attrs)) //No value at all (should always match, but will trim for consistency)
				tok["attr_" + att] = "1";
		}
		return 1;
	}
}
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
		while (sscanf(t, "%s\uFFFA%c%s\uFFFB%s", string before, int type, string info, string after)) {
			output += before;
			switch (type)
			{
				case 'u': output += replace(texts[(int)info], (["<": "&lt;", "&": "&amp;"])); break;
				case 'e': {
					sscanf(info, "%s:%s", string id, string text);
					if ((int)id) output += sprintf("<img src=\"https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0\" title=%q alt=%<q>", (int)id, text);
					else output += sprintf("<img src=\"https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/1.0\" title=%q alt=%<q>", id, text);
				}
				default: break; //Should this put a noisy error in?
			}
			t = after;
		}
		return output + t;
	}
	//Allow a blockquote to become a dialog
	string blockquote(string text, mapping token)
	{
		if (string tag = m_delete(token, "attr_tag")) {
			//If the blockquote starts with an H3, it is some form of title.
			if (sscanf(text, "<h3%*[^>]>%s</h3>%s", string title, string main)) switch (tag) {
				//For dialogs, the title is outside the scroll context, and also gets a close button added.
				case "dialog": return sprintf("<dialog%s><section>"
					"<header><h3>%s</h3><div><button type=button class=dialog_cancel>x</button></div></header>"
					"<div>%s</div>"
					"</section></dialog>",
				attrs(token), title || "", main);
				case "details": return sprintf("<details%s><summary>%s</summary>%s</details>",
					attrs(token), title || "Details", main);
				default: break; //No special title handling
			}
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token), text);
		}
		return ::blockquote(text, token);
	}
	string heading(string text, int level, string raw, mapping token)
	{
		if (options->headings && !options->headings[level])
			//Retain the first-seen heading of each level
			options->headings[level] = text;
		return ::heading(text, level, raw, token);
	}
	//Allow a link to be a button (or anything else)
	string link(string href, string title, string text, mapping token)
	{
		if (_parse_attrs("{" + href + "}", token)) {
			//Usage: [Text](: attr=value)
			string tag = m_delete(token, "attr_tag") || "button";
			if (tag == "button" && !token->attr_type) token->attr_type = "button";
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token, ([])), text);
		}
		return ::link(href, title, text, token);
	}
}
class Lexer
{
	inherit Parser.Markdown.Lexer;
	object_program lex(string src)
	{
		::lex(src);
		foreach (tokens; int i; mapping tok)
		{
			if (tok->type == "paragraph" && tok->text[-1] == '}')
			{
				mapping target = tok;
				array(string) lines = tok->text / "\n";
				if (i + 1 < sizeof(tokens) && tokens[i + 1]->type == "blockquote_end") target = tokens[i + 1];
				else if (sizeof(lines) == 1 && i > 0)
				{
					//It's a paragraph consisting ONLY of attributes.
					//Attach the attributes to the preceding token.
					//TODO: Only do this if the preceding token is a
					//type that can take attributes.
					target = tokens[i - 1];
				}
				if (_parse_attrs(lines[-1], target))
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
						if (_parse_attrs(tokens[j]->text, tok))
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

@"G->G->template_defaults";
mapping(string:mixed) render_template(string template, mapping(string:string|function(string|void:string)|mapping) replacements)
{
	string content;
	if (has_value(template, '\n')) {content = template; template = "<inline>.md";}
	else content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template + "\n");
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template + "\n");
	if (replacements->vars) {
		//Set vars to a mapping of variable name to value and they'll be made available to JS.
		//To trigger automatic synchronization, set ws_type to a keyword, and ws_group to a string or int.
		//Provide a static file that exports render(state). By default, that's the same name
		//as the ws_type (so if ws_type is "raidfinder", it'll load "raidfinder.js"), but
		//this can be overridden by explicitly setting ws_code.
		string jsonvar(array nv) {return sprintf("let %s = %s;", nv[0], Standards.JSON.encode(nv[1], 5));}
		array vars = jsonvar(sort((array)(replacements->vars - (["ws_code":""])))[*]);
		if (replacements->vars->ws_type) {
			string code = replacements->vars->ws_code || replacements->vars->ws_type;
			if (!has_suffix(code, ".js")) code += ".js";
			vars += ({
				jsonvar(({"ws_code", G->G->template_defaults["static"](code)})),
				"let ws_sync = null; import('" + G->G->template_defaults["static"]("ws_sync.js") + "').then(m => ws_sync = m);",
			});
		}
		replacements->js_variables = "<script>" + vars * "\n" + "</script>";
	}
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
		string|function repl = replacements[token] || G->G->template_defaults[token];
		if (!repl)
		{
			if (dflt) pieces[i] = dflt;
			else error("Token %O not found in templates/%s\n", "$$" + token + "$$", template);
		}
		else if (callablep(repl)) pieces[i] = repl(dflt);
		else pieces[i] = repl;
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
			//Dynamic defaults - can be overridden, same as static defaults can
			"title": headings[1] || "StilleBot",
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

int(1bit) is_localhost_mod(string login, string ip) {
	return login && login == persist_config["ircsettings"]->nick && //Allow mod status if you're me,
		NetUtils.is_local_host(ip) && //from here,
		G->G->menuitems->chan_->get_active(); //and we're allowing me to pretend to be a mod
}

//An HTTP handler, a websocket handler, and Markdown
class http_websocket
{
	inherit http_endpoint;
	inherit websocket_handler;

	string ws_type; //Will be set in create(), but can be overridden (also in create) if necessary
	constant markdown = ""; //Override this with a hash-quoted inline Markdown file

	//Override to signal if a group name (the part without the channel name) requires
	//mod privileges. If not overridden, all groups are open to non-mods.
	bool need_mod(string grp) { }
	//Provide channel state this way, or override get_state and do everything
	mapping get_chan_state(object channel, string grp, string|void id) { }

	protected void create(string name) {
		::create(name);
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		if (!ws_type) ws_type = name;
	}
	mapping(string:mixed) render(Protocols.HTTP.Server.Request req, mapping replacements) {
		if (replacements->vars->?ws_group) {
			if (!replacements->vars->ws_type) replacements->vars->ws_type = ws_type;
			if (req->misc->channel) replacements->vars->ws_group += req->misc->channel->name;
		}
		if (markdown != "") return render_template(markdown, replacements);
		return render_template(ws_type + ".md", replacements);
	}

	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (!has_prefix(ws_type, "chan_")) return 0;
		[object channel, string grp] = split_channel(msg->group);
		if (!channel) return "Bad channel";
		string login = conn->session->user->?login;
		if (channel->name == "#!demo") {
			if (!is_localhost_mod(login, conn->remote_ip)) conn->session = ([
				"fake": 1,
				"user": ([
					"broadcaster_type": "fakemod", //Hack :)
					"display_name": "!Demo",
					"id": "3141592653589793", //Hopefully Twitch doesn't get THAT many users any time soon. If this ever shows up in logs, it should be obvious.
					"login": "!demo",
				]),
			]);
			conn->is_mod = 1;
		}
		else conn->is_mod = channel->mods[login] || is_localhost_mod(login, conn->remote_ip);
		if (!conn->is_mod && need_mod(grp)) return "Not logged in";
	}

	mapping get_state(string group, string|void id) {
		[object channel, string grp] = split_channel(group);
		if (!channel) return 0;
		return get_chan_state(channel, grp, id);
	}
}

mapping(string:mixed) redirect(string url, int|void status)
{
	mapping resp = (["error": status||302, "extra_heads": (["Location": url])]);
	if (status == 301) return resp; //301 redirects are allowed to be cached.
	resp->extra_heads->Vary = "*"; //Try to stop 302 redirects from being cached
	resp->extra_heads["Cache-Control"] = "no-store";
	return resp;
}

mapping(string:mixed) jsonify(mixed data, int|void jsonflags)
{
	return (["data": string_to_utf8(Standards.JSON.encode(data, jsonflags)), "type": "application/json"]);
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
		"user:edit", "user:edit:broadcast", "user:read:follows", "user:edit:follows",
		"user:read:broadcast", "user:read:email",
		"channel:read:redemptions", "channel:manage:redemptions",
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
	protected void create(multiset(string)|void scopes) {
		mapping cfg = persist_config["ircsettings"];
		::create(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", scopes);
	}
	Concurrent.Future request_access_token_promise(string code) {
		return Concurrent.Promise(lambda(function ... cb) {
			request_access_token(code) {cb[!__ARGS__[0]](__ARGS__[1]);};
		});
	}
	//Promisified version of refresh_access_token not necessary with Twitch's current "never-expire" policy
}

mapping(string:mixed) twitchlogin(Protocols.HTTP.Server.Request req, multiset(string) scopes, string|void next)
{
	mapping resp = render_template("login.md", (["scopes": ((array)scopes - ({""})) * " "]));
	req->misc->session->redirect_after_login = next || req->full_query; //Shouldn't usually be necessary
	return resp;
}

//Make sure we have a logged-in user. Returns 0 if the user is already logged in, or
//a response that should be sent before continuing.
//if (mapping resp = ensure_login(req)) return resp;
//Provide a space-separated list of scopes to also ensure that these scopes are active.
mapping(string:mixed) ensure_login(Protocols.HTTP.Server.Request req, string|void scopes)
{
	if (req->misc->session->fake) return 0; //In demo mode, pretend you're logged in (as the demo channel owner)
	multiset havescopes = req->misc->session->?scopes;
	multiset wantscopes = scopes ? (multiset)(scopes / " ") : (<>);
	wantscopes[""] = 0; //Remove any empty entry, just in case
	multiset bad = wantscopes - TwitchAuth()->list_valid_scopes();
	if (sizeof(bad)) return (["error": 500, "type": "text/plain", 
		"data": sprintf("Internal server error: Unrecognized scope %O being requested", (array)bad * " ")]);
	if (!havescopes) return twitchlogin(req, wantscopes); //Even if you aren't requesting any scopes
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	if (sizeof(needscopes) > sizeof(havescopes)) return twitchlogin(req, needscopes);
	//If we get here, it's all good, carry on.
}

//Make sure we have a broadcaster token with at least the given scopes. Returns 0 if we do, or a space-separated list of scopes.
//Note that this should always be called with at least one scope, otherwise it may return a spurious zero if not logged in.
string ensure_bcaster_token(Protocols.HTTP.Server.Request req, string scopes, string|void chan) {
	if (req->misc->session->fake) return scopes; //There'll never be a valid broadcaster login with fake mod mode active
	if (!chan) chan = req->misc->channel->name[1..];
	array havescopes = (persist_status->path("bcaster_token_scopes")[chan]||"") / " " - ({""});
	if (req->misc->session->user->?login == chan && !sizeof((multiset)havescopes - req->misc->session->scopes)) {
		//The broadcaster is logged in, with at least as much scope as we previously
		//had. Upgrade bcaster_token to this token.
		persist_status->path("bcaster_token")[chan] = req->misc->session->token;
		persist_status->path("bcaster_token_scopes")[chan] = sort(havescopes = indices(req->misc->session->scopes)) * " ";
		persist_status->save();
	}
	multiset wantscopes = (multiset)(scopes / " ");
	multiset needscopes = (multiset)havescopes | wantscopes;
	if (sizeof(needscopes) > sizeof(havescopes)) return sort(indices(needscopes)) * " ";
}

//User text will be given to the given user_text object; emotes will be markdowned.
//If autolink is specified, words that look like links will be made links.
//Note that this is probably a bit too restrictive. Feel free to add more, just as
//long as nothing abusable can be recognized by this, as it won't be passed through
//user_text for normal safety.
object hyperlink = Regexp.PCRE("^http(s|)://[A-Za-z0-9.]+(/[-A-Za-z0-9/.+]*|)(\\?[A-Za-z0-9=&+]*|)(#[A-Za-z0-9]*|)$");
string emotify_user_text(string text, object user, int|void autolink)
{
	mapping emotes = G->G->emote_code_to_markdown;
	if (!emotes) return user(text);
	array words = text / " ";
	//This is pretty inefficient - it makes a separate user() entry for each
	//individual word. If this is a problem, consider at least checking for
	//any emotes at all, and if not, just return user(text) instead.
	foreach (words; int i; string w)
		if (emotes[w]) words[i] = emotes[w];
		//TODO: Retain emote IDs rather than the markdown for them, then support modified emotes
		//else if (sscanf(w, "%s_%s", string base, string mod) && mod && sizeof(mod) == 2 && emotes[base])
			//words[i] = synthesize_emote()
		else if (autolink && hyperlink->match(w)) words[i] = sprintf("[%s](%<s)", w);
		else words[i] = user(w);
	return words * " ";
}
