//Twitch-oriented IRC connection
//This is generic (connection.pike has all the StilleBot-specific code), but is
//aimed at supporting Twitch and not arbitrary IRC servers. For instance, since
//Twitch has the tags feature, this will automatically parse tags, even though
//that might not actually be a standard feature.

//TODO: Version the TwitchIRC class too somehow. If it changes, force reconnect
//on all clients.

//Connections can be reused. Callbacks will be replaced automatically when the
//irc_callback object is initialized.
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
		//Look up the latest version of the callback container. If that isn't the one we were
		//set up to call, don't reconnect.
		object current_module = current_callbacks[function_name(object_program(options->module))];
		if (!options->no_reconnect && options->module == current_module) connect();
		else if (!options->outdated) options->module->irc_closed(options);
	}

	void sockread(mixed _, string data) {
		buf += data;
		while (sscanf(buf, "%s\n%s", string line, buf)) {
			line -= "\r";
			if (line == "") continue;
			line = utf8_to_string(line);
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
			if (function f = this["command_" + args[0]]) f(attrs, prefix, args);
			else if ((int)args[0]) command_0000(attrs, prefix, args);
			else TRACE("Unrecognized command received: %O\n", line);
		}
		if (sizeof(buf)) TRACE("Buffer remaining: %O\n", buf);
	}

	void sockwrite() {
		//TRACE("Socket writable.\n");
		//Send the next thing from the queue
		if (!sizeof(queue)) return;
		[mixed next, queue] = Array.shift(queue);
		if (stringp(next)) {
			int sent = sock->write(next + "\n");
			if (sent < sizeof(next) + 1) {
				//Partial send. Requeue all but the part that got sent.
				//In the unusual case that we send the entire message apart
				//from the newline at the end, we will store an empty string
				//into the queue, which will then cause a "blank line" to be
				//sent, thus finishing the line correctly.
				TRACE("Partial write, requeueing\n");
				queue = ({next[sent..]}) + queue;
				return; //Don't poke the socket until it's actually writable again
			}
		}
		else if (functionp(next)) next(this);
		else error("Unknown entry in queue: %t\n", next);
		call_out(sockwrite, 0.125); //TODO: Figure out a safe rate limit. Or do we even need one?
	}

	void enqueue(mixed ... items) {
		if (!sizeof(queue)) call_out(sockwrite, 0);
		queue += items;
	}
	Concurrent.Future promise() {
		return Concurrent.Promise(lambda(function res, function rej) {
			enqueue(res);
			//TODO: Call rej() on error
			//TODO: If the other end code gets updated, allow the promise to be migrated
			//(by removing the old callback and putting in a new one). You can always
			//augment by adding another call to promise().
		});
	}

	void send(string channel, string msg) {
		enqueue("privmsg #" + (channel - "#") + " :" + replace(msg, "\n", " "));
	}

	int(0..1) update_options(mapping opt) {
		//TODO: Check for a version incompatibility. If code version has changed, return 1.
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
		//Channels can be joined and parted freely.
		array havechan = Array.arrayify(options->join);
		array wantchan = Array.arrayify(opt->join);
		//For some reason, these automaps are raising warnings about indexing
		//empty strings. I don't get it.
		array commands = ("CAP REQ :twitch.tv/" + (wantopt - haveopt)[*])
			+ ("JOIN " + (wantchan - havechan)[*])
			+ ("PART " + (havechan - wantchan)[*]);
		if (sizeof(commands)) enqueue(@commands);
		options->module = opt->module;
	}

	void close() {sock->close();} //Close the socket immediately
	void queueclose() {enqueue(close);} //Close the socket once we empty what's currently in queue
	void quit() {enqueue("quit", no_reconnect);} //Ask the server to close once the queue is done
	void no_reconnect() {options->no_reconnect = 1;}

	void command_473(mapping attrs, string pfx, array(string) args) {
		//Failed to join channel. Reject promise?
	}
	void command_0000(mapping attrs, string pfx, array(string) args) {
		//Handle all unknown numeric responses (currently by ignoring them)
	}
	void command_USERSTATE(mapping attrs, string pfx, array(string) args) { }
	void command_ROOMSTATE(mapping attrs, string pfx, array(string) args) { }
	void command_JOIN(mapping attrs, string pfx, array(string) args) { }
	void command_PING(mapping attrs, string pfx, array(string) args) {
		enqueue("pong :" + args[1]);
	}
	void command_CAP(mapping attrs, string pfx, array(string) args) { } //We assume Twitch supports what they've documented
	//Send all types of message through, let the callback sort 'em out
	void command_PRIVMSG(mapping attrs, string pfx, array(string) args) {
		options->module->irc_message(@args, attrs);
	}
	function command_NOTICE = command_PRIVMSG, command_USERNOTICE = command_PRIVMSG;
}

//Inherit this to listen to connection responses
class irc_callback {
	mapping connection_cache;
	protected void create(string name) {
		connection_cache = current_callbacks[name]->?connection_cache || ([]);
		current_callbacks[name] = this;
	}
	//The type is PRIVMSG, NOTICE, USERNOTICE; chan begins "#"; attrs may be empty mapping but will not be null
	void irc_message(string type, string chan, string msg, mapping attrs) { }
	void irc_closed(mapping options) { } //Called only if we're not reconnecting

	Concurrent.Future irc_connect(mapping options) {
		options = (["module": this]) | (options || ([]));
		//TODO: If user not specified, fetch user and pass from persist_config
		//TODO: If pass not specified, fetch from bcaster_token, if authenticated for chat
		object conn = connection_cache[options->user];
		//If the connection exists, give it a chance to update itself. Normally
		//it will do so, and return 0; otherwise, it'll return 1, we disconnect
		//it, and start fresh. Problem: We could have multiple connections in
		//parallel for a short while. Alternate problem: Waiting for the other
		//to disconnect could leave us stalled if anything goes wrong. Partial
		//solution: The old connection is kept, but flagged as outdated. This
		//can be seen in callbacks.
		if (conn && conn->update_options(options)) {
			TRACE("Update failed, reconnecting\n");
			conn->options->outdated = 1;
			conn->quit();
			conn = 0;
		}
		else if (conn) TRACE("Retaining across update\n");
		if (!conn) conn = TwitchIRC(options);
		connection_cache[options->user] = conn;
		return conn->promise();
	}
}

protected void create() {
	add_constant("irc_callback", irc_callback);
}
