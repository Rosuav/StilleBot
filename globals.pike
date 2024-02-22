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
//(echo them all, in order). Mappings and arrays can nest arbitrarily; for example:
//- "single message"
//- ({"sequential", "messages"})
//- (["message": "text to send", "attr": "value"])
//- (["message": ({"sequential", "messages"}), "attr": "value"])
typedef string|mapping(string:mixed)|array(_echoable_message)|zero _echoable_message;
//To avoid recompilation ambiguities, the added constant is simply a reference to the
//(private) recursive typedef above.
typedef _echoable_message echoable_message;
//DEPRECATED. If you actually need to support functions, do so explicitly. Support for
//functions is itself deprecated and should eventually be removed.
typedef echoable_message|function(object,object,string:echoable_message) command_handler;

//Case-fold command names. For consistency, use this everywhere; that way,
//commands will be created and found correctly. TODO eventually: Switch
//this out for a proper Unicode casefold.
string command_casefold(string cmd) {return lower_case(cmd);}

//Attempt to find a "likely command" for a given channel.
//If it returns 0, there's no such command. It may return a function
//that eventually fails, but it will attempt to do so as rarely as
//possible; returning nonzero will NORMALLY mean that the command is
//fully active.
echoable_message|function find_command(object channel, string cmdname, int is_mod, int|void is_vip)
{
	//Prevent commands from containing a hash, as that was formerly used for
	//per-channel commands. This can be relaxed in the future if needed.
	if (has_value(cmdname, '#')) return 0;
	if (has_value(cmdname, '!')) return 0; //Pseudo-commands can't be run as normal commands
	mixed cmd = channel->commands[command_casefold(cmdname)];
	if (!mappingp(cmd)) return cmd; //This includes if it's not found
	if (cmd->access == "mod" && !is_mod) return 0;
	if (cmd->access == "vip" && !is_mod && !is_vip) return 0;
	if (cmd->access == "none") return 0;
	//If we get here, the command is acceptable.
	return cmd;
}

//List all broadly-active channels' config mappings
//Eventually this may start excluding channels that are deemed "inactive", eg if they
//haven't been logged in or gone live in (say) three months; such channels could still be
//located by ID (see get_channel_config), but might be skipped over for autocommands
//and other features.
//NOTE: This returns non-live copies of config. Do not mutate them. If you need
//mutable config for a channel, look up its object in G->G->irc and use that.
array(mapping) list_channel_configs() {
	//NOTE: This may be quite inefficient, but hopefully with filesystem caching, it
	//will be good enough.
	array files = "channels/" + glob("*.json", get_dir("channels"))[*];
	return Standards.JSON.decode_utf8(Stdio.read_file(files[*])[*]);
}

//Return a Second or a Fraction representing the given ISO time, or 0 if unparseable
Calendar.ISO.Second time_from_iso(string time) {
	if (object ts = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", time)) return ts;
	return Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s.%f%z", time);
}

//Handle potentially-asynchronous results. Can be used to paper over a distinction between
//async and sync functions (forcing them all to be async).
__async__ mixed spawn_task(mixed gen) {
	return objectp(gen) && gen->on_await ? await(gen) : gen;
}

//If cb is a spawn_task->pump/propagate_error function, return the corresponding task, else 0.
mixed find_callback_task(function cb) {
	object obj = function_object(cb);
	//Note: Don't check if the program is exactly spawn_task from above, since code
	//might have been reloaded. This should be able to recognize older-instance tasks.
	if (function_name(object_program(obj)) == "spawn_task") return obj;
}

//await(task_sleep(seconds)); //Delay the current task efficiently
Concurrent.Future task_sleep(int|float delay) {
	return Concurrent.resolve(0)->delay(delay);
}

//Run a subprocess and yield (["rc": returncode, "stdout": bytes sent to stdout])
//Similar to Process.run() but doesn't do stderr or stdin (and should only be used with small data).
class run_process {
	inherit Concurrent.Promise;
	Stdio.File stdout = Stdio.File();
	protected void create(array(string) command, mapping|void modifiers) {
		Process.create_process(command, (modifiers || ([]))
			| (["callback": done, "stdout": stdout->pipe(Stdio.PROP_IPC)]));
	}
	void done(object proc) {
		if (proc->status() == 2) success((["rc": proc->wait(), "stdout": stdout->read()]));
	}
}


//Some bot features are available for commands to call on.
//The name is somewhat archaic now, and "builtin" would probably serve better.
//Or maybe something different again. Whatever. They're builtin_command for hysterical raisins.
@"G->G->builtins";
class builtin_command {
	constant builtin_description = ""; //Label used in any human-readable context - one line description of purpose
	constant command_description = ""; //Deprecated: Description for the default response
	constant builtin_name = ""; //Short human-readable name for the drop-down
	constant builtin_param = ""; //Label(s) for the parameter(s), or "/Label/option/option/option" to offer specific selections. If blank, has no parameter. May be an array for multiple params.
	constant vars_provided = ([ ]); //List all available vars (it's okay if they aren't all always provided)
	constant command_suggestions = 0; //Set this to provide some suggestions (which will show up as enableable features)
	constant scope_required = ""; //If nonblank, will be offered as a suggestion any time this builtin is used. TODO: Make this more flexible, so some parameters can ask for scope, others not?

	//Override this either as-is or as a continue function to return the useful params.
	//Note that the person mapping may be as skeletal as (["user": "Nobody"]) - all
	//other keys are optional.
	//The params will be an array of as many strings as builtin_param contains (if it's
	//a string directly, that's equivalent to an array of that one string).
	mapping|Concurrent.Future message_params(object channel, mapping person, array params, mapping cfg) { }

	protected void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->builtins[name] = this;
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

int channel_uptime(int channel)
{
	if (object started = G->G->stream_online_since[channel])
		return started->distance(Calendar.now())->how_many(Calendar.Second());
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

//TODO: Make this callable, move the functionality for hooks into here, and maybe fold "inherit hook" into "inherit annotated"?
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
	if (functionp(handler)) werror("WARNING: Deprecated use of register_hook() - use 'inherit hook' instead\n");
	string origin = functionp(handler) ? Program.defined(function_program(handler)) : handler;
	//Trim out any hooks for this event that were defined in the same class
	//"Same class" is identified by its textual origin, rather than the actual
	//identity of the program, such that a reloaded/updated version of a class
	//counts as the same one as before.
	G->G->hooks[event] = filter(G->G->hooks[event] || ({ }),
		lambda(array(string|function) f) {return f[0] != origin;}
	) + ({({origin, handler})}) * functionp(handler);
}

int runhooks(string event, string|zero skip, mixed ... args)
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

@"G->G->exports";
class annotated {
	protected void create(string name) {
		//TODO: Find a good way to move prev handling into the export class or object below
		mapping prev = G->G->exports[name];
		G->G->exports[name] = ([]);
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (objectp(anno) && anno->is_callable_annotation) anno(this, name, key);
			}
		}
		//Purge any that are no longer being exported (handles renames etc)
		if (prev) foreach (prev - G->G->exports[name]; string key;)
			add_constant(key);
	}
}
object export = class {
	constant is_callable_annotation = 1;
	protected void `()(object module, string modname, string key) {
		add_constant(key, module[key]);
		G->G->exports[modname][key] = 1;
	}
}();

object retain = class {
	constant is_callable_annotation = 1;
	protected void `()(object module, string modname, string key) {
		if (!G->G[key]) G->G[key] = module[key];
		else module[key] = G->G[key];
	}
}();

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
	//be given if update_one was called, otherwise it will be 0. Type is rarely needed
	//but is used only in conjunction with an ID.
	mapping|Concurrent.Future get_state(string|int group, string|void id, string|void type) { }
	//__async__ mapping get_state(string|int group, string|void id, string|void type) { } //Alternate (equivalent) signature

	//Override to validate any init requests. Return 0 to allow the socket
	//establishment, or an error message.
	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) { }

	//If msg->cmd is "init", it's a new client and base processing has already been done.
	//If msg is 0, a client has disconnected and is about to be removed from its group.
	//Use websocket_groups[conn->group] to find an array of related sockets.
	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (!msg) return;
		if (msg->cmd == "refresh" || msg->cmd == "init") send_update(conn);
		if (function f = this["websocket_cmd_" + msg->cmd]) f(conn, msg);
	}

	void _low_send_updates(mapping resp, array(object) socks) {
		if (!resp) return;
		string text = Standards.JSON.encode(resp | (["cmd": "update"]), 4);
		foreach (socks, object sock)
			if (sock && sock->state == 1) sock->send_text(text);
	}
	void _send_updates(array(object) socks, string|int group, mapping|void data) {
		if (!data) data = get_state(group);
		if (objectp(data) && data->then) data->then() {_low_send_updates(__ARGS__[0], socks);};
		else _low_send_updates(data, socks);
	}

	//Send an update to a specific connection. If not provided, data will
	//be generated by get_state(). TODO: Is this used anywhere? If not,
	//replace it with send_message() and have it not add cmd:update. Would
	//be more useful.
	void send_update(mapping(string:mixed) conn, mapping|void data) {
		_send_updates(({conn->sock}), conn->group, data);
	}

	//Update all connections in a given group.
	//Generates just one state object and sends it everywhere.
	void send_updates_all(string|int group, mapping|void data) {
		array dest = websocket_groups[group];
		if (!dest) {
			//If you attempt to send updates to "control#rosuav", send them instead
			//to "control#49497888", assuming there weren't any sockets for the former.
			[object channel, string subgroup] = split_channel(group);
			if (channel) dest = websocket_groups[subgroup + "#" + channel->userid];
		}
		if (dest && sizeof(dest)) _send_updates(dest, group, data);
	}
	//Compatibility overlap variant form. Use this with a channel object to send to
	//the correct group for that channel.
	variant void send_updates_all(object chan, string|int group, mapping|void data) {
		send_updates_all(group + "#" + chan->userid, data);
	}

	void update_one(string|int group, string id, string|void type) {
		spawn_task(get_state(group, id, type))->then() {
			send_updates_all(group, (["id": id, "data": __ARGS__[0], "type": type || "item"]));
		};
	}
	//Compatibility overlap variant form, as above.
	variant void update_one(object chan, string|int group, string id, string|void type) {
		update_one(group + "#" + chan->userid, id, type);
	}

	//Returns ({channel, subgroup}) - if channel is 0, it's not valid
	array(object|string) split_channel(string|void group) {
		if (!stringp(group) || !has_value(group, '#')) return ({0, ""}); //Including if we don't have a group set yet
		sscanf(group, "%s#%s", string subgroup, string chan);
		//Allow the channel to be identified by Twitch ID
		//Note: If the channel name is entirely digits, it cannot reliably be specified by name.
		if ((string)(int)chan == chan) return ({G->G->irc->id[(int)chan], subgroup});
		return ({G->G->irc->channels["#" + chan], subgroup});
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

array(string) token_for_user_login(string login) {
	mapping cred = G->G->user_credentials[lower_case(login)];
	if (cred) return ({cred->token, cred->scopes * " "});
	return ({"", ""});
}

array(string) token_for_user_id(int|string userid) {
	mapping cred = G->G->user_credentials[(int)userid];
	if (cred) return ({cred->token, cred->scopes * " "});
	return ({"", ""});
}

//Token bucket system, shared among all IRC connections.
float request_rate_token(string user, string chan, int|void lowprio) {
	//By default, messages are limited to 20 every 30 seconds.
	int bucket_size = 20;
	int window_size = 30;
	float safety_shave = 0.0; //For small windows, it's reasonable to shave the safety margin.
	array bucket = G->G->irc_token_bucket[user + chan];
	if (!bucket) G->G->irc_token_bucket[user + chan] = bucket = ({0, 0});
	if (chan == "#!login") {
		//Logins are limited to 20 every 10 seconds, per user. Probably never an issue.
		window_size = 10; bucket_size = 20;
	}
	else if (chan == "#!join") {
		//Channel joinings are limited to 20 every 10 seconds, per user; however, they are
		//usually going to be batched (multiple channels in a single JOIN command), so for
		//simplicity and safety, we instead lock to one JOIN command per user with a ten
		//second cooldown before the next one is permitted.
		int now = time();
		if (bucket[0] > now) return bucket[0] - now;
		bucket[0] = now + 11.0; //safety margin
		return 0;
	}
	else if (chan == "#" + user || G->G->user_mod_status[user + chan])
		//You can spam harder in channels you mod for.
		bucket_size = 100;
	else if (has_suffix(chan, "-nonmod")) {
		//HACK: Non-mods also have to restrict themselves to one message per second.
		bucket_size = window_size = 1;
		safety_shave = 0.875; //Safety margin of 1/8 sec is plenty when working with a window of one second.
	}
	else if (float wait = request_rate_token(user, chan + "-nonmod"))
		//Other half of hack: If you're not a mod, check both limits.
		return wait;
	int now = time() / window_size; //I'm pretty sure "number of half-minutes since 1970" isn't the way most humans think about time.
	if (now != bucket[0]) {bucket[0] = now; bucket[1] = 0;} //New time period, fresh bucket of tokens.
	if (bucket[1] < bucket_size) {bucket[1]++; return 0;} //Tokens available - take one and pass it on, like your IQ was normal
	//We're out of tokens. Notify the caller to wait.
	//For safety's sake, we wait until one second past the next window.
	//Note that we do not automatically consume a token from the next window;
	//if you get a float back from this function, you do NOT have permission
	//yet, and must re-request a token after the delay.
	//To calculate the required delay, we find the time_t of the next window,
	//that being the (now+1)th window, plus the safety second. Asking Pike
	//how many seconds since an epoch in the future returns a negative number,
	//and negating that number gives us the time until that instant.
	return -time(window_size * (now + 1) + 1) - safety_shave + (lowprio * window_size / 10.0);
}

#ifdef IRCTRACE
#define _IRCTRACE werror
#else
void _IRCTRACE(mixed ... ignore) { }
#endif
/* Available options:
module		Override the default selection of callbacks and module version
user		User to log in as. With module, defines connection caching.
pass		OAuth password. If omitted, uses the user token.
capabilities	Optional array of caps to request
join		Optional array of channels to join (include the hashes)
login_commands	Optional commands to be sent after (re)connection
encrypt		Set to 1 to require encryption, -1 to require unencrypted.
		The default will change at some point such that most are encrypted.
lowprio		Reduce priority by some value 1-9, default 0 is highest priority
*/
@"G->G->irc_callbacks"; @"G->G->irc_token_bucket"; @"G->G->user_mod_status";
class _TwitchIRC(mapping options) {
	constant server = "irc.chat.twitch.tv"; //Port 6667 or 6697 depending on SSL status
	string ip; //Randomly selected from the A/AAAA records for the server.
	string pass; //Pulled out of options in case options gets printed out

	Stdio.File|SSL.File sock;
	array(string) queue = ({ }); //Commands waiting to be sent, and callbacks
	array(function) failure_notifs = ({ }); //All will be called on failure
	int have_connection = 0;
	int writing = 1; //If not writing and need to write, immediately write.
	string readbuf = "";
	int last_rcv_time = 0; //time_t of last line received
	constant PING_INTERVAL = 300; //Time between PING messages sent
	mixed ping_callout;

	//Messages in this set will not be traced on discovery as we know them.
	constant ignore_message_types = (<
		"USERSTATE", "ROOMSTATE", "JOIN", "PONG",
		"CAP", //We assume Twitch supports what they've documented
	>);

	protected void create() {
		array ips = gethostbyname(server); //TODO: Support IPv6
		if (!ips || !sizeof(ips[1])) error("Unable to gethostbyname for %O\n", server);
		ip = random(ips[1]);
		connect();
		pass = m_delete(options, "pass");
	}
	void connect() {
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(sockread, connected, connfailed);
		sock->connect(ip, options->encrypt >= 1 ? 6697 : 6667); //Will throw on error
		//Until we get connected, hold, waiting for our marker.
		//The establishment of the connection will insert login
		//commands before this.
		have_connection = 0; queue += ({await_connection});
		readbuf = "";
		last_rcv_time = time();
	}

	void connected() {
		if (!sock) {werror("ERROR IN IRC HANDLING: connected() with sock == 0!\n%O\n", options); fail("Didn't actually connect"); return;}
		if (options->encrypt >= 1) { //Make this and the above ">= 0" to change default to be encrypted
			sock = SSL.File(sock, SSL.Context());
			sock->connect(server);
		}
		array login = ({
			"PASS " + pass,
			"NICK " + options->user,
			"USER " + options->user + " localhost 127.0.0.1 :StilleBot",
		});
		//PREPEND onto the queue.
		queue = login
			+ sprintf("CAP REQ :twitch.tv/%s", Array.arrayify(options->capabilities)[*])
			+ map(Array.arrayify(options->join) / 20.0) {return "JOIN :" + __ARGS__[0] * ",";}
			+ Array.arrayify(options->login_commands)
			+ ({"MARKER"})
			+ queue;
		sock->set_nonblocking(sockread, sockwrite, sockclosed);
		if (!ping_callout) ping_callout = call_out(send_ping, PING_INTERVAL);
	}

	void connfailed() {fail("Connection failed.");}
	void fail(string how) {
		failure_notifs(({how + "\n", backtrace()}));
		//Since we're rejecting all the promises, we should dispose of the
		//queued success functions. But this is a failure mode anyway, so
		//for simplicity, just dispose of the entire queue.
		failure_notifs = queue = ({ });
		sock->close();
	}

	void sockclosed() {
		_IRCTRACE("Connection closed.\n");
		//Look up the latest version of the callback container. If that isn't the one we were
		//set up to call, don't reconnect.
		object current_module = G->G->irc_callbacks[options->module->modulename];
		if (!options->no_reconnect && options->module == current_module) call_out(connect, 0);
		else if (!options->outdated) options->module->irc_closed(options);
		sock = 0;
		remove_call_out(ping_callout);
	}

	void sockread(mixed _, string data) {
		readbuf += data;
		while (sscanf(readbuf, "%s\n%s", string line, readbuf)) {
			line -= "\r";
			if (line == "") continue;
			line = utf8_to_string(line);
			if (options->verbose) werror("IRC < %O\n", line);
			last_rcv_time = time();
			//Twitch messages with TAGS capability begin with the tags
			sscanf(line, "@%s %s", string tags, line);
			//Most messages from the server begin with a prefix. It's
			//irrelevant to many Twitch messages, but for where it's
			//wanted, it is passed along to the raw command handlers.
			//The only part that is usually interesting is the user
			//name, which we add to the attrs.
			sscanf(line, ":%s %s", string prefix, line);
			//A lot of messages end with a colon-prefixed string.
			sscanf(line, "%s :%s", line, string str);
			//With all that removed, what's left must be the command and
			//its parameters. (Only the last parameter is allowed to be
			//an arbitrary string, the rest must be atoms.)
			array args = line / " " - ({""});
			if (str) args += ({str});
			if (!sizeof(args)) continue; //Broken command
			mapping attrs = ([]);
			if (tags) foreach (tags / ";", string att) {
				sscanf(att, "%s=%s", string name, string val);
				attrs[replace(name, "-", "_")] = replace(val || "", "\\s", " ");
			}
			if (prefix) sscanf(prefix, "%s%*[!.]", attrs->user);
			if (!have_connection && args * " " == "NOTICE * Login authentication failed") {
				//Don't pass this failure along to the module; it's a failure to connect.
				fail("Login authentication failed.");
				return;
			}
			if (!have_connection && args * " " == "NOTICE * Improperly formatted auth") {
				//This is also a failure to connect, but a code bug rather than auth failure.
				fail("Login authentication format error, check oauth: prefix.");
				return;
			}
			if (function f = this["command_" + args[0]]) f(attrs, prefix, args);
			else if ((int)args[0]) command_0000(attrs, prefix, args);
			else if (has_value(options->module->messagetypes, args[0])) {
				//Pass these on to the module
				if (sizeof(args) == 1) args += ({""}); //No channel. What should happen here?
				else if (!has_prefix(args[1], "#")) args[1] = "#" + args[1]; //Some messages, for unknown reason, have channels without the leading hash. Why?!
				if (sizeof(args) == 2) args += ({""}); //No message, pass an empty string along
				options->module->irc_message(@args, attrs);
			}
			else if (!ignore_message_types[args[0]])
				_IRCTRACE("Unrecognized command received: %O\n", line);
		}
	}

	void sockwrite() {
		//Send the next thing from the queue
		if (!sizeof(queue) || !sock) {writing = 0; return;}
		[mixed next, queue] = Array.shift(queue);
		if (stringp(next)) {
			//Automatic rate limiting
			string autolim;
			if (has_prefix(next, "JOIN ")) autolim = "#!join";
			else if (sscanf(next, "PRIVMSG %s :", string c) && c) autolim = c;
			if (float wait = autolim && request_rate_token(options->user, autolim, options->lowprio)) {
				queue = ({next}) + queue;
				call_out(sockwrite, wait);
				return;
			}
			if (options->verbose) werror("IRC > %O\n", replace(next, pass, "<password>")); //hunter2 :)
			int sent = sock->write(next + "\n");
			if (sent < sizeof(next) + 1) {
				//Partial send. Requeue all but the part that got sent.
				//In the unusual case that we send the entire message apart
				//from the newline at the end, we will store an empty string
				//into the queue, which will then cause a "blank line" to be
				//sent, thus finishing the line correctly.
				_IRCTRACE("Partial write, requeueing\n");
				queue = ({next[sent..]}) + queue;
			}
			return;
		}
		else if (intp(next) || floatp(next)) {call_out(sockwrite, next); return;} //Delay.
		else if (functionp(next)) next(this); //func <=> ({func, this}), because the queue could get migrated to a new object
		else if (arrayp(next) && sizeof(next) && functionp(next[0])) next[0](@next[1..]);
		else error("Unknown entry in queue: %t\n", next);
		call_out(sockwrite, 0.125); //TODO: Figure out a safe rate limit. Or do we even need one?
	}

	void enqueue(mixed ... items) {
		if (!writing) {writing = 1; call_out(sockwrite, 0);}
		queue += items;
	}
	Concurrent.Future promise() {
		if (!sizeof(queue)) return Concurrent.resolve(this);
		return Concurrent.Promise(lambda(function res, function rej) {
			enqueue() {failure_notifs -= ({rej}); res(@__ARGS__);};
			failure_notifs += ({rej});
		});
	}

	void send(string channel, string msg, mapping(string:string)|void tags) {
		//Tags can be client-nonce and/or reply-parent-msg-id
		string pfx = "";
		if (tags && sizeof(tags)) pfx = "@" + map((array)tags) {
			//Invert the transformation of incoming messages
			return replace(__ARGS__[0][0], "_", "-") + "=" + replace(__ARGS__[0][1], " ", "\\s");
		} * " " + " ";
		enqueue(pfx + "PRIVMSG #" + (channel - "#") + " :" + string_to_utf8(replace(msg, "\n", " ")));
	}

	void send_ping() {
		if (!sock) return;
		if (last_rcv_time < time() - PING_INTERVAL * 2) {
			//It's been two ping intervals since we last heard from the server.
			//Note that this counts PONG messages, but also everything else.
			sock->close();
			sockclosed();
			return;
		}
		ping_callout = call_out(send_ping, PING_INTERVAL);
		enqueue(); queue = ({"ping :stillebot"}) + queue; //Prepend to queue
	}

	int(0..1) update_options(mapping opt) {
		if (!sock || !sock->is_open()) return 1; //We've lost the connection. Fresh connect.
		werror("update_options mod %O user %O - sock is %O\n", options->module, options->user, sock);
		//If the IRC handling code has changed incompatibly, reconnect.
		if (opt->version != options->version) return 1;
		//If you explicitly ask to be reconnected, do so.
		if (opt->force_reconnect) return 1;
		//If credentials have changed, reconnect.
		if (opt->pass != pass) return 1; //The user is the same, or cache wouldn't have pulled us up.
		if (Array.arrayify(opt->login_commands) * "\n" !=
			Array.arrayify(options->login_commands) * "\n") return 1; //No way of knowing whether it's compatible or not
		//Capabilities can be added, but not removed. Since the client might be
		//expecting results based on the exact set given, if any are removed, we
		//just disconnect.
		array haveopt = Array.arrayify(options->capabilities);
		array wantopt = Array.arrayify(opt->capabilities);
		if (sizeof(haveopt - wantopt)) return 1;
		//Channels can be parted freely. For dependability, we (re)join all
		//the channels currently wanted, but first part what's not.
		array havechan = Array.arrayify(options->join);
		array wantchan = Array.arrayify(opt->join);
		//For some reason, these automaps are raising warnings about indexing
		//empty strings. I don't get it.
		array commands = ("CAP REQ :twitch.tv/" + (wantopt - haveopt)[*]);
		if (sizeof(havechan - wantchan)) commands += ({"PART :" + (havechan - wantchan) * ","});
		if (sizeof(wantchan - havechan)) commands += map((wantchan - havechan) / 20.0) {return "JOIN :" + __ARGS__[0] * ",";};
		if (sizeof(commands)) enqueue(@commands);
		options = opt; m_delete(options, "pass"); //Transfer all options. Anything unchecked is assumed to be okay to change like this.
	}

	void close() {sock->close();} //Close the socket immediately
	void queueclose() {enqueue(close);} //Close the socket once we empty what's currently in queue
	void quit() {enqueue("quit", no_reconnect);} //Ask the server to close once the queue is done
	void no_reconnect() {options->no_reconnect = 1;}
	void yes_reconnect() {options->no_reconnect = 0;}

	void await_connection() {
		//Wait until we have seen the error response to the MARKER
		if (!have_connection) queue = ({.25, this_function}) + queue;
	}
	void command_421(mapping attrs, string pfx, array(string) args) {
		//We send this command after the credentials. If we get this without
		//first seeing any failures of login, then we assume the login worked.
		if (sizeof(args) > 2 && args[2] == "MARKER") have_connection = 1;
	}
	void command_473(mapping attrs, string pfx, array(string) args) {
		//Failed to join channel. Reject promise?
		werror("IRC: Failed to join channel: %O %O %O %O\n", options->user, attrs, pfx, args);
	}
	multiset command_0000_ignore = (<"001", "002", "003", "004", "353", "366", "372", "375", "376">);
	void command_0000(mapping attrs, string pfx, array(string) args) {
		//Handle all unknown numeric responses
		if (command_0000_ignore[args[0]]) return;
		werror("IRC: Unknown numeric response: %O %O %O %O\n", options->user, attrs, pfx, args);
	}
	void command_PING(mapping attrs, string pfx, array(string) args) {
		enqueue("pong :" + args[1]); //Enqueue or prepend to queue?
	}
	void command_RECONNECT(mapping attrs, string pfx, array(string) args) {
		werror("#### Got a RECONNECT signal #### %s %s", options->user, ctime(time()));
		if (sock) sock->close();
		sockclosed();
	}
	//Insert ({get_token, "#some_channel"}) into the queue to grab a token before
	//proceeding. This is done automatically for PRIVMSG and JOIN commands, but for
	//anything else, the same token buckets can be used.
	void get_token(string chan) {
		float wait = request_rate_token(options->user, chan, options->lowprio);
		//No token available? Delay, then re-request.
		if (wait) queue = ({wait, ({get_token, chan})}) + queue;
	}
	//TODO: If msg_ratelimit comes in, retry last message????
}

//Inherit this to listen to connection responses
class irc_callback {
	mapping connection_cache;
	string modulename;
	constant messagetypes = ({ });
	protected void create(string name) {
		modulename = name;
		connection_cache = G->G->irc_callbacks[name]->?connection_cache || ([]);
		G->G->irc_callbacks[name] = this;
	}
	//The type is one of the ones in messagetypes; chan begins "#"; attrs may be empty mapping but will not be null
	void irc_message(string type, string chan, string msg, mapping attrs) { }
	//Called only if we're not reconnecting. Be sure to call the parent.
	void irc_closed(mapping options) {m_delete(connection_cache, options->user);}

	Concurrent.Future irc_connect(mapping options) {
		//Bump this version number when there's an incompatible change. Old
		//connections will all be severed.
		options = (["module": this, "version": 11]) | (options || ([]));
		if (!options->user) {
			//Default credentials from the bot's main configs
			mapping cred = G->G->dbsettings->credentials;
			if (!cred->token) return Concurrent.reject(({"IRC authentication not configured\n", backtrace()}));
			options->user = cred->username; options->pass = "oauth:" + cred->token;
		}
		options->user = lower_case(options->user); //Casefold for the cache, don't have multiples kthx
		if (!options->pass) {
			string chan = lower_case(options->user);
			mapping cred = G->G->user_credentials[chan];
			if (!cred) return Concurrent.reject(({"No broadcaster auth for " + chan + "\n", backtrace()}));
			//Note that we accept chat:read even if there are commands that would require
			//chat:edit permission. This isn't meant to be a thorough check, just a quick
			//confirmation that we really are trying to work with chat here.
			if (!has_value(cred->scopes, "chat:edit") && !has_value(cred->scopes, "chat:read"))
				return Concurrent.reject(({"No chat auth for " + chan + "\n", backtrace()}));
			options->pass = "oauth:" + cred->token;
		}
		object|zero conn = connection_cache[options->user];
		//If the connection exists, give it a chance to update itself. Normally
		//it will do so, and return 0; otherwise, it'll return 1, we disconnect
		//it, and start fresh. Problem: We could have multiple connections in
		//parallel for a short while. Alternate problem: Waiting for the other
		//to disconnect could leave us stalled if anything goes wrong. Partial
		//solution: The old connection is kept, but flagged as outdated. This
		//can be seen in callbacks.
		if (conn && conn->update_options(options)) {
			_IRCTRACE("Update failed, reconnecting\n");
			conn->options->outdated = 1;
			conn->quit();
			conn = 0;
		}
		else if (conn) _IRCTRACE("Retaining across update\n");
		if (!conn) conn = _TwitchIRC(options);
		connection_cache[options->user] = conn;
		return conn->promise();
	}
}

string emote_url(string id, int|void size) {
	if (!intp(size) || !size || size > 3) size = 3;
	else if (size < 1) size = 1;
	if (has_prefix(id, "/")) {
		//Cheer emotes use a different URL pattern.
		if (size == 3) size = 4; //Cheer emotes have sizes 1, 1.5, 2, 3, 4, but 3 is really 2.5, and 4 is really 3.
		sscanf(id, "/%s/%d", string pfx, int n);
		//Cheering N bits will choose the nearest non-larger emote to N.
		//TODO maybe: Get these from the lookup table Twitch returns?
		if (n >= 10000) n = 10000;
		else if (n >= 5000) n = 5000;
		else if (n >= 1000) n = 1000;
		else if (n >= 100) n = 100;
		else n = 1;
		return sprintf("https://d3aqoihi2n8ty8.cloudfront.net/actions/%s/light/animated/%d/%d.gif",
			lower_case(pfx), n, size);
	}
	return sprintf("https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/%d.0", id, size);
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
					output += sprintf("<img src=%q title=%q alt=%<q>", emote_url(id, 1), text);
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
				case "dialogform": case "formdialog": //(allow this to be spelled both ways)
				case "dialog": return sprintf("<dialog%s><section>"
						"<header><h3>%s</h3><div><button type=button class=dialog_cancel>x</button></div></header>"
						"<div>%s%s%s</div>"
						"</section></dialog>",
					attrs(token), title || "",
					tag == "dialog" ? "" : "<form method=dialog>",
					main,
					tag == "dialog" ? "" : "</form>",
				);
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
		if (sscanf(href, "%s :%s", string dest, string att) && _parse_attrs("{:" + att + "}", token)) {
			//Usage: [Text](https://link.example/destination/ :attr=value)
			string tag = m_delete(token, "attr_tag") || "a";
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token, (["href": dest])), text);
		}
		return ::link(href, title, text, token);
	}
}
class Lexer
{
	inherit Parser.Markdown.Lexer;
	this_program lex(string src)
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
mapping(string:mixed) render_template(string template, mapping replacements)
{
	string content;
	if (has_value(template, '\n')) {content = template; template = "<inline>.md";}
	else content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template + "\n");
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template + "\n");
	function static_fn = G->G->template_defaults["static"];
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
				jsonvar(({"ws_code", static_fn(code)})),
				"let ws_sync = null; import('" + static_fn("ws_sync.js") + "').then(m => ws_sync = m);",
			});
		}
		replacements->js_variables = "<script>" + vars * "\n" + "</script>";
	}
	replacements->head_scripts = "";
	//Set js to a string or an array of strings, and those files will be loaded.
	if (replacements->js) foreach (Array.arrayify(replacements->js), string fn) {
		if (!has_value(fn, ".")) fn += ".js";
		replacements->head_scripts += "<script type=module src=\"" + static_fn(fn) + "\"></script>\n";
	}
	//Similarly for CSS files.
	if (replacements->css) foreach (Array.arrayify(replacements->css), string fn) {
		if (!has_value(fn, ".")) fn += ".css";
		replacements->head_scripts += "<link rel=\"stylesheet\" href=\"" + static_fn(fn) + "\">\n";
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

//The TEXTFORMATTING widget in utils.js creates a bunch of form elements. Save these
//element names into a mapping, then call textformatting_css on that mapping, and you
//will get back the correct CSS text for the specified formatting.
//** NOTE ** Always ensure that every attribute in this array is handled by both
//textformatting_css and textformatting_validate. Both of them will happily accept
//mappings with other attributes, but must poke every textformatting attribute.
array TEXTFORMATTING_ATTRS = ("font fontweight fontstyle fontsize fontfamily whitespace css "
			"color strokewidth strokecolor borderwidth bordercolor "
			"bgcolor bgalpha padvert padhoriz textalign "
			"shadowx shadowy shadowcolor shadowalpha") / " ";
string textformatting_css(mapping cfg) {
	string css = cfg->css || "";
	if (css != "" && !has_suffix(css, ";")) css += ";";
	foreach ("color font-weight font-style border-color white-space text-align" / " ", string attr)
		if (mixed val = cfg[attr - "-"]) css += attr + ": " + val + ";";
	foreach ("font-size width height" / " ", string attr) //FIXME: This is processing width and height, which aren't text formatting attrs
		if (mixed val = cfg[attr - "-"]) css += attr + ": " + val + "px;";
	if (cfg->font && cfg->fontfamily) css += "font-family: " + cfg->font + ", " + cfg->fontfamily + ";"; //Note that the front end may have other work to do too, but here, we just set the font family.
	else if (cfg->font || cfg->fontfamily) css += "font-family: " + (cfg->font || cfg->fontfamily) + ";";
	if ((float)cfg->padvert) css += sprintf("padding-top: %gem; padding-bottom: %<gem;", (float)cfg->padvert);
	if ((float)cfg->padhoriz) css += sprintf("padding-left: %gem; padding-right: %<gem;", (float)cfg->padhoriz);
	if (cfg->strokewidth && cfg->strokewidth != "None")
		css += sprintf("-webkit-text-stroke: %s %s;", cfg->strokewidth, cfg->strokecolor || "black");
	if (int alpha = (int)cfg->shadowalpha) {
		//NOTE: If we do more than one filter, make sure we combine them properly here on the back end.
		string col = cfg->shadowcolor || "";
		if (sizeof(col) != 7 || col[0] != '#') col = "#000000"; //I don't know how to add alpha to something that isn't in hex.
		css += sprintf("filter: drop-shadow(%dpx %dpx %s%02X);",
			(int)cfg->shadowx, (int)cfg->shadowy,
			col, (int)(alpha * 2.55 + 0.5));
	}
	if (int alpha = (int)cfg->bgalpha) {
		string col = cfg->bgcolor || "";
		if (sizeof(col) != 7 || col[0] != '#') col = "#000000"; //As above. Since <input type=color> is supposed to return hex, this should be safe.
		css += sprintf("background-color: %s%02X;", col, (int)(alpha * 2.55 + 0.5));
	}
	//If you set a border width, assume we want a solid border. (For others, set the
	//entire border definition in custom CSS.)
	if ((int)cfg->borderwidth) css += sprintf("border-width: %dpx; border-style: solid;", (int)cfg->borderwidth);
	return css;
}
//Validate the textformatting attributes. Ignores any other attributes.
//Where possible, attrs will be mutated to ensure safety (eg int/str cast).
//Invalid attributes will be removed from cfg; if any were, 0 is returned,
//otherwise 1 is. Either way, the config mapping is at that point safe.
//Note that the "css" attribute is only very cursorily checked.
constant _textformatting_kwdattr = ([
	"fontstyle": ({"normal", "italic", "oblique"}), //Technically "oblique <angle>" is supported, but I reject it here for simplicity
	"whitespace": ({"normal", "nowrap", "pre", "pre-wrap", "pre-line", "break-spaces"}),
	"textalign": ({"start", "end", "center", "justify"}), //There are other options, but not all formalized. This may need to support a fill character some day.
	"fontfamily": ({"serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "emoji", "math", "fangsong"}),
]);
int(1bit) textformatting_validate(mapping cfg) {
	int ok = 1;
	//Integer attributes. Note that "0" will be retained, but "" will be removed (and is not an error).
	foreach ("fontsize borderwidth bgalpha shadowx shadowy shadowalpha" / " ", string attr)
		if (mixed val = cfg[attr]) {
			if (val == "") m_delete(cfg, attr);
			else if (intp(val)) cfg[attr] = (string)val; //Not an error, but let's go with strings for consistency
			else if (!stringp(val)) {m_delete(cfg, attr); ok = 0;}
			else if (val != (string)(int)val) {m_delete(cfg, attr); ok = 0;} //Should we be merciful about whitespace?
		}
	//Float attributes. Similar, but more flexible with formatting. Note that we will reformat them.
	foreach ("padhoriz padvert" / " ", string attr)
		if (mixed val = cfg[attr]) {
			if (val == "") m_delete(cfg, attr);
			else if (intp(val) || floatp(val)) cfg[attr] = (string)val; //Not an error, but let's go with strings for consistency
			else if (!stringp(val)) {m_delete(cfg, attr); ok = 0;}
			else cfg[attr] = (string)(float)val;
		}
	//Colors. In textformatting_css(), shadowcolor is further mandated to be a hex color, but
	//for now, we accept more forms.
	foreach ("color strokecolor bordercolor bgcolor shadowcolor" / " ", string attr) if (mixed val = cfg[attr]) {
		if (has_value(({4,5,7,9}), sizeof(val)) && sscanf(val, "#%x%s", int n, string tail) && tail == "")
			//#RGB, #RGBA, #RRGGBB, #RRGGBBAA
			cfg[attr] = sprintf("#%0" + (sizeof(val) - 1) + "X", n);
		//Keywords. Currently not actually validating whether it's a recognized color
		//name, just whether it's syntactically a keyword.
		else if (sscanf(val, "%[a-zA-Z]", string col) && col == val) ;
		//Maybe consider adding rgb() functional notation, in case?
		//All the others, no, just reject them.
		else {m_delete(cfg, attr); ok = 0;}
	}
	//Keyword attributes. These must all be one of their specified keywords, although blank is not an error.
	foreach (_textformatting_kwdattr; string attr; array valid) {
		if (!cfg[attr] || has_value(valid, cfg[attr])) ;
		else if (m_delete(cfg, attr) != "") ok = 0;
	}
	//The last few, needing individual validation.
	if (mixed val = cfg->css) {
		if (!stringp(val)) {m_delete(cfg, "css"); ok = 0;}
		//At the moment, I'm being way too permissive here. It'd be nice to have
		//a basic syntactic check (eg no close brace), not because actual abuse
		//is likely, but because a typo would cause bizarre and hard-to-diagnose
		//formatting errors (instead of simply affecting this element, it'd break
		//styling for other things too). But it'd need to be a proper check, not
		//just "does this have a close brace in it", since quoted strings are OK.
	}
	if (mixed val = cfg->fontweight) {
		//Font weight can be one of a handful of keywords, OR a number.
		if (val == "") m_delete(cfg, "fontweight");
		else if (stringp(val) && has_value(({"normal", "bold", "lighter", "bolder"}), val)) ;
		else if ((int)val >= 1 && (int)val <= 1000) cfg->fontweight = (string)(int)val;
		else {m_delete(cfg, "fontweight"); ok = 0;}
	}
	if (mixed val = cfg->font) {
		//The font is allowed to be a series of values separated by commas.
		//Each value can be a quoted string or an atom.
		array fonts = ({ });
		while (sscanf(val, "%*[ ]\"%[^\"]\"%s", string font, string tail) == 3 //eg >>"Lucida Sans"<<
				|| sscanf(val, "%*[ ]%[-A-Za-z ]%s", font, tail) == 3) { //eg >>Lucida Sans<<
			if (font == "") break;
			fonts += ({font});
			if (!tail || tail == "" || sscanf(tail, "%*[ ],%s", val) != 2 || val == "") break;
		}
		//Quote all font names that aren't single-word atoms. CSS does allow
		//(but does not recommend) multi-atom names without quotes, but let's not.
		cfg->font = map(fonts) {[string font] = __ARGS__;
			if (sscanf(font, "%*[-A-Za-z]%s", string tail) && tail == "") return font;
			return sprintf("%q", font);
		} * ", ";
	}
	if (mixed val = cfg->strokewidth) {
		if (intp(val)) cfg->strokewidth = val + "px";
		else if (!stringp(val)) {m_delete(cfg, "strokewidth"); ok = 0;}
		else if (val == "None") ; //"None" is basically 0px but won't give the directives at all (however, it won't inherit)
		else if (sscanf(val, "%dpx", int n) && n) cfg->strokewidth = n + "px";
		else {m_delete(cfg, "strokewidth"); ok = 0;}
	}
	return 1;
}

int(1bit) is_localhost_mod(string login, string ip) {
	return login && login == G->G->dbsettings->credentials->username && //Allow mod status if you're me,
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
	mapping annotation_lookup;

	//Override to signal if a group name (the part without the channel name) requires
	//mod privileges. If not overridden, all groups are open to non-mods.
	bool need_mod(string grp) { }
	//Provide channel state this way, or override get_state and do everything
	mapping|Concurrent.Future get_chan_state(object channel, string grp, string|void id, string|void type) { }
	//__async__ mapping get_chan_state(object channel, string grp, string|void id, string|void type) { } //Alternate (equivalent) signature

	protected void create(string name) {
		annotation_lookup = mkmapping(indices(this), annotations(this)); //This could go somewhere else, it's likely to be useful for more than just this class
		::create(name);
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		if (!ws_type) ws_type = name;
	}
	mapping(string:mixed) render(Protocols.HTTP.Server.Request req, mapping replacements) {
		if (replacements->vars->?ws_group) {
			if (!replacements->vars->ws_type) replacements->vars->ws_type = ws_type;
			if (req->misc->channel) replacements->vars->ws_group += "#" + req->misc->channel->userid;
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
		else conn->is_mod = G->G->user_mod_status[login + channel->name] || is_localhost_mod(login, conn->remote_ip);
		if (!conn->is_mod && need_mod(grp)) return "Not logged in";
		conn->subgroup = grp;
	}

	mapping|Concurrent.Future get_state(string group, string|void id, string|void type) {
		[object channel, string grp] = split_channel(group);
		if (!channel) return 0;
		return get_chan_state(channel, grp, id, type);
	}

	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		::websocket_msg(conn, msg);
		string name = "wscmd_" + msg->?cmd;
		function f = this[name]; if (!f) return;
		[object channel, string grp] = split_channel(conn->group);
		if (!channel || conn->session->fake) return;
		if (annotation_lookup[name] && annotation_lookup[name]["is_mod"] && !conn->is_mod) return;
		//TODO: If it returns (possibly asynchronously) a mapping, send that back, with
		//cmd set to the incoming cmd. This will allow a convenient request/response.
		//TODO: What about non-category connections? Should this be handled by websocket_handler?
		f(channel, conn, msg);
	}
	/* Example:
	@"is_mod": void wscmd_do_the_thing(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	Without the decorator, anyone can use it; with it, only mods can.
	*/
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

mapping all_twitch_scopes = ([
	//Scopes last updated from https://dev.twitch.tv/docs/authentication/scopes/ 20230324
	//Those whose descriptions begin with an asterisk should be marked with a warning label.
	"analytics:read:extensions": "View analytics data for Twitch Extensions",
	"analytics:read:games": "View analytics data for games",
	"bits:read": "See cheers and the bits leaderboard",
	"channel:edit:commercial": "*Run ads (broadcaster only)",
	"channel:manage:broadcast": "*Configure broadcast incl category, title, and VOD markers (editor only)",
	"channel:read:charity": "See charity campaign details",
	"channel:manage:extensions": "*Activate and deactivate extensions for a channel",
	"channel:manage:moderators": "*Add/remove mod swords (broadcaster only)",
	"channel:manage:polls": "*Start and end polls",
	"channel:manage:predictions": "*Start and end predictions",
	"channel:manage:raids": "*Go raiding (broadcaster only)",
	"channel:manage:redemptions": "*Create and manage channel point rewards and redemptions",
	"channel:manage:schedule": "*Update the channel broadcast schedule",
	"channel:manage:videos": "*Delete VODs",
	"channel:manage:vips": "*Add/remove VIP badges (broadcaster only)",
	"channel:read:editors": "See who is an editor for the channel",
	"channel:read:goals": "View goals (eg follower/subscriber counts)",
	"channel:read:hype_train": "See hype train status and get notifications",
	"channel:read:polls": "View a current poll in progress and get notifications",
	"channel:read:predictions": "View a current prediction in progress and get notifications",
	"channel:read:redemptions": "*See channel point rewards and redemptions",
	"channel:read:stream_key": "*See your stream key and stream on your behalf",
	"channel:read:subscriptions": "*See who's subscribed to your channel",
	"channel:read:vips": "List current channel VIPs",
	"clips:edit": "*Create clips of the current broadcast",
	"moderation:read": "See who's banned, who's a mod, etc",
	"moderator:manage:announcements": "*Send announcements",
	"moderator:manage:automod": "Make decisions on automodded messages",
	"moderator:read:automod_settings": "See Automod settings",
	"moderator:manage:automod_settings": "*Change Automod settings",
	"moderator:manage:banned_users": "*Ban/timeout/unban users",
	"moderator:read:blocked_terms": "See currently-blocked words and phrases",
	"moderator:manage:blocked_terms": "*Change the blocked words/phrases list",
	"moderator:manage:chat_messages": "*Delete individual chat messages",
	"moderator:read:chat_settings": "View chat restrictions eg slow mode",
	"moderator:manage:chat_settings": "*Set/remove chat restrictions eg slow mode",
	"moderator:read:chatters": "See who's currently in chat",
	"moderator:read:followers": "List your channel followers and get notified on new follows",
	"moderator:read:shield_mode": "See whether shield mode is active and get notified when it's activated",
	"moderator:manage:shield_mode": "*Engage/disengage shield mode",
	"moderator:read:shoutouts": "Get notified when you shout out or get shouted out",
	"moderator:manage:shoutouts": "*Send shoutouts",
	"user:edit": "*Update the user's description",
	"user:edit:follows": "*Deprecated - no longer functional (was follow/unfollow)",
	"user:manage:blocked_users": "*Block or unblock other users",
	"user:read:blocked_users": "*See who you've blocked (not the same as banned from the channel)",
	"user:read:broadcast": "See which Twitch extensions you're using",
	"user:edit:broadcast": "*Activate and deactivate extensions for a user",
	"user:manage:chat_color": "*Change chat color",
	"user:read:email": "See your email address",
	"user:read:follows": "*See who you follow",
	"user:read:subscriptions": "*Check if you are subscribed to a channel",
	"user:manage:whispers": "*Send whispers (requires phone auth)",
	//Chat/PubSub scopes
	"channel:moderate": "*Perform and see moderation actions in a channel",
	"chat:edit": "*Send chat messages",
	"chat:read": "View chat messages as they happen",
	"whispers:read": "*View your whispers as they arrive",
	"whispers:edit": "*Send whispers (may no longer be functional)",
	//Deprecated scopes which may or may not have equivalents above
	"user_subscriptions": "*Deprecated - view your subscriptions",
	"user_read": "Deprecated - view your email address",
	"chat_login": "*Deprecated - send chat messages",
	"viewing_activity_read": "*Deprecated - see your viewing activity",
	"user_blocks_edit": "*Deprecated - Block/unblock users",
	"user_blocks_read": "*Deprecated - See who you've blocked",
	"communities_edit": "*Deprecated - join/leave communities",
	"communities_moderate": "*Deprecated - community moderation",
	"channel_subscriptions": "*Deprecated - See who is subscribed to your channel",
	"collections_edit": "*Deprecated - Manage your channel's collections",
	"channel_read": "*Deprecated - View channel configuration (category, title, etc) including your stream key",
	"channel_stream": "*Deprecated - Reset your stream key (probably nonfunctional now)",
	"channel_feed_read": "Deprecated - View channel feed",
	"channel_feed_edit": "*Deprecated - Post to your channel feed",
	"channel_commercial": "*Deprecated - Run an ad",
	"channel_editor": "*Deprecated - Cut VODs, update channel title and category, etc",
	"channel_check_subscription": "*Deprecated - check if someone's subbed to your channel",
	//New as of 20231021:
	"channel:read:ads": "View ad schedule and status", "channel:manage:ads": "Snooze ads", //Been asking for these for ages!
	"user:read:chat": "Read chat using webhooks", "user:write:chat": "Send chat via the API",
	"channel:bot": "Use app access for a channel", "user:bot": "Use app access for a user",
	//New as of 20230111:
	"user:read:moderated_channels": "See which channels you're a mod for",
]);

class TwitchAuth
{
	inherit Web.Auth.OAuth2.Client;
	constant OAUTH_AUTH_URI  = "https://id.twitch.tv/oauth2/authorize";
	constant OAUTH_TOKEN_URI = "https://id.twitch.tv/oauth2/token";
	protected multiset(string) valid_scopes = (multiset)indices(all_twitch_scopes);
	protected void create(multiset(string)|void scopes, string|void host) {
		mapping cfg = persist_config["ircsettings"];
		if (host) host = "https://" + host; //HTTPS is mandatory for login anyway, so just assume that the request came in encrypted
		else host = cfg->http_address; //The configured address includes the protocol.
		::create(cfg->clientid, cfg->clientsecret, host + "/twitchlogin", scopes);
	}
	Concurrent.Future request_access_token_promise(string code) {
		return Concurrent.Promise(lambda(function ... cb) {
			request_access_token(code) {cb[!__ARGS__[0]](__ARGS__[1]);};
		});
	}
	//Promisified version of refresh_access_token not necessary with Twitch's current "never-expire" policy
}

mapping(string:mixed) _twitchlogin(Protocols.HTTP.Server.Request req, multiset(string) scopes) {
	return render_template("login.md", (["scopes": ((array)scopes - ({""})) * " "]) | (req->misc->chaninfo || ([])));
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
	if (!havescopes) return _twitchlogin(req, wantscopes); //Even if you aren't requesting any scopes
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	if (sizeof(needscopes) > sizeof(havescopes)) return _twitchlogin(req, needscopes);
	//If we get here, it's all good, carry on.
}

//Make sure we have a broadcaster token with at least the given scopes. Returns 0 if we do, or a space-separated list of scopes.
//Note that this should always be called with at least one scope, otherwise it may return a spurious zero if not logged in.
string ensure_bcaster_token(Protocols.HTTP.Server.Request req, string scopes, string|void chan) {
	if (req->misc->session->fake) return scopes; //There'll never be a valid broadcaster login with fake mod mode active
	if (!chan) chan = req->misc->channel->name[1..];
	array havescopes = G->G->user_credentials[chan]->?scopes || ({ });
	multiset wantscopes = (multiset)(scopes / " ");
	multiset needscopes = (multiset)havescopes | wantscopes;
	if (sizeof(needscopes) > sizeof(havescopes)) return sort(indices(needscopes)) * " ";
}

//Figure out the most suitable host name to represent us. If a person went to the URL
//"https://sikorsky.rosuav.com:6789/foo/bar", this should return "sikorsky.rosuav.com:6789".
//Respects configuration settings about the use of Apache forwarding.
string deduce_host(mapping request_headers) {
	mapping cfg = persist_config["ircsettings"];
	if (string fwd = cfg->http_forwarded && request_headers["x-forwarded-host"]) return fwd;
	if (string host = request_headers["host"]) return host;
	sscanf(cfg->http_address || "://", "%*s://%s", string dflt);
	return dflt; //Might be 0 if we get nothing whatsoever, but that's highly unlikely
}

//When automatically linkifying links, use this regex for consistency.
//Note that this is probably a bit too restrictive. Feel free to add more, just as
//long as nothing abusable can be recognized by this. It's also okay if it doesn't
//match every possible link, as this is meant as a courtesy, not a validator.
object hyperlink = Regexp.PCRE("^http(s|)://[A-Za-z0-9.]+(/[-A-Za-z0-9/.+]*|)(\\?[A-Za-z0-9=&+]*|)(#[A-Za-z0-9]*|)$");

//True if the bot is definitely active, or false if uncertain or not active.
int(1bit) is_active_bot() {
	string active = G->G->dbsettings->?active_bot;
	if (!active || active == "") return 0; //Might be there's no active bot, or maybe we just don't know for sure.
	sscanf(persist_config["ircsettings"]->?http_address || "://", "%*s://%s%*[:]", string host);
	return host == active;
}

//Return the currently-active bot, or 0 if we don't know for sure
string|zero get_active_bot() {
	string active = G->G->dbsettings->?active_bot;
	return active != "" && active;
}
