//Twitch-oriented IRC connection
//This is generic (connection.pike has all the StilleBot-specific code), but is
//aimed at supporting Twitch and not arbitrary IRC servers. For instance, since
//Twitch has the tags feature, this will automatically parse tags, even though
//that might not actually be a standard feature.

//Connections can be reused. Callbacks will be replaced automatically when the
//irc_callback program is initialized.
mapping current_callbacks = ([]);
#define TRACE werror

/* Available options:

module		Override the default selection of callbacks and module version
user		User to log in as. With module, defines connection caching.
pass		OAuth password
capabilities	Optional array of caps to request
join		Optional array of channels to join (include the hashes)
login_commands	Optional commands to be sent after (re)connection

*/
class TwitchIRC(mapping options) {
	constant server = "irc.chat.twitch.tv";
	constant port = 6667;
	string ip; //Randomly selected from the A/AAAA records for the server.
	string pass; //Pulled out of options in case options gets printed out

	Stdio.File sock;
	array(string) queue = ({ }); //Commands waiting to be sent, and callbacks
	string buf = "";

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
		sock->connect(ip, port); //Will throw on error
		TRACE("Connecting to %O : %O\n", ip, port);
	}

	void connected() {
		TRACE("Connected.\n");
		werror("%O\n", options);
		array login = ({
			"PASS " + pass,
			"NICK " + options->user,
			"USER " + options->user + " localhost 127.0.0.1 :StilleBot",
		});
		//PREPEND onto the queue.
		queue = login
			+ sprintf("CAP REQ :twitch.tv/%s", Array.arrayify(options->capabilities)[*])
			+ sprintf("JOIN %s", Array.arrayify(options->join)[*])
			+ Array.arrayify(options->login_commands)
			+ queue;
		sock->set_nonblocking(sockread, sockwrite, sockclosed);
	}

	void connfailed() {
		TRACE("Connect failed.\n");
		//TODO: Report failure to any waiting promise. We weren't able to get a connection.
	}

	void sockclosed() {
		TRACE("Connection closed.\n");
		//TODO: Retry connection, unless the caller's gone.
		if (options->module == current_callbacks[function_name(options->module)]) connect();
	}

	void sockread(mixed _, string data) {
		buf += data;
		TRACE("Sock read: %O\n", data);
	}

	void sockwrite() {
		TRACE("Socket writable.\n");
		//Send the next thing from the queue
		if (!sizeof(queue)) return;
		[mixed next, queue] = Array.shift(queue);
		if (stringp(next)) sock->write(next + "\r\n");
		call_out(sockwrite, 0.125); //TODO: Figure out a safe rate limit. Or do we even need one?
	}

	Concurrent.Future promise() {
		return Concurrent.Promise(lambda(function res, function rej) {
			queue += ({res});
			//TODO: Call rej() on error
			//TODO: If the other end code gets updated, allow the promise to be migrated
			//(by removing the old callback and putting in a new one). You can always
			//augment by adding another call to promise().
		});
	}
}

//Inherit this to listen to connection responses
class irc_callback {
	mapping connection_cache;
	protected void create(string name) {
		name = function_name(this_program); //Ignore the passed-in name and rely on the program name
		connection_cache = current_callbacks[name]->?connection_cache || ([]);
		current_callbacks[name] = this_program;
	}
	void irc_notify(mixed ... args) { }
	void irc_message(mixed ... args) { }
	void irc_closed(mixed ... args) { } //Called only if we're not reconnecting

	Concurrent.Future irc_connect(mapping options) {
		options = (["module": this_program]) | (options || ([]));
		//TODO: If user not specified, fetch user and pass from persist_config
		//TODO: If pass not specified, fetch from bcaster_token, if authenticated for chat
		object conn = connection_cache[options->user];
		if (conn) {
			//TODO: Poke the connection and make sure it's actually alive
			conn->update_options(options);
		} else {
			connection_cache[options->user] = conn = TwitchIRC(options);
		}
		return conn->promise();
	}
}

#if !constant(G)
void _unhandled_error(mixed err) {werror("Unhandled asynchronous exception\n%s\n", describe_backtrace(err));}
void _ignore_result(mixed value) { }
int(0..1) is_genstate(mixed x) {return functionp(x) && has_value(sprintf("%O", x), "\\u0000");}
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
#endif

class SomeModule {
	inherit irc_callback;

	continue Concurrent.Future say_hello(string channel) {
		mapping config = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"));
		object irc = yield(irc_connect(([
			"user": "rosuav", "pass": config->ircsettings->pass,
			"join": channel,
		])));
		irc->send(channel, "Hello, world");
		irc->queueclose();
	}

	void irc_closed(mapping options) {
		write("Shutting down!\n");
		exit(0);
	}
}

int main() {
	spawn_task(SomeModule("somemodule.pike")->say_hello("#rosuav"));
	return -1;
}
