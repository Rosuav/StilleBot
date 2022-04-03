//Twitch-oriented IRC connection
//This is generic (connection.pike has all the StilleBot-specific code), but is
//aimed at supporting Twitch and not arbitrary IRC servers. For instance, since
//Twitch has the tags feature, this will automatically parse tags, even though
//that might not actually be a standard feature.

//Connections can be reused. It is assumed that any given module will only use
//a single connection for any user; if that's not the case, invent a different
//module name to distinguish them. Connecting again will update the options,
//notably changing the callbacks, but will retain the same socket connection.
mapping connection_cache = ([]);
#define TRACE werror

class TwitchIRC(mapping options) {
	constant server = "irc.chat.twitch.tv";
	constant port = 6667;
	string ip; //Randomly selected from the A/AAAA records for the server.

	Stdio.File sock = Stdio.File();
	array(string) queue = ({ }); //Commands waiting to be sent, and callbacks
	string buf = "";

	protected void create() {
		array ips = gethostbyname(server); //TODO: Support IPv6
		if (!ips || !sizeof(ips[1])) error("Unable to gethostbyname for %O\n", server);
		ip = random(ips[1]);
		sock->open_socket();
		sock->set_nonblocking(sockread, connected, connfailed);
		sock->connect(ip, port); //Will throw on error
	}

	void connected() {
		TRACE("Connected.\n");
		sock->set_nonblocking(sockread, sockwrite, sockclosed);
	}

	void connfailed() {
		TRACE("Connect failed.\n");
		//TODO: Report failure to any waiting promise. We weren't able to get a connection.
	}

	void sockclosed() {
		TRACE("Connection closed.\n");
		//TODO: Retry connection, unless the caller's gone.
		//This might require a versioning system: active connections get retriggered with the
		//new version, inactive ones languish with the old version, and on disconnect, get
		//dropped.
	}

	void sockread(mixed _, string data) {
		buf += data;
	}

	void sockwrite() {
		//Send the next thing from the queue
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

Concurrent.Future connect(mapping options) {
	//If there's no existing connection, establish one.
	//If there is one, poke it?
	//return conn->promise();
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

continue Concurrent.Future say_hello(string channel) {
	object irc = yield(connect(([
		"user": "rosuav", "pass": "fetch from settings",
		"join": channel,
	])));
	irc->send(channel, "Hello, world");
	irc->queueclose();
}

int main() {
	spawn_task(say_hello("#rosuav"));
}
