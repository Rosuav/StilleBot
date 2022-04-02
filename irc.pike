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

class TwitchIRC(string username, mapping options) {
	constant server = "irc.chat.twitch.tv";
	string ip; //Randomly selected from the A/AAAA records for the server.

	Stdio.File sock = Stdio.File();
	array(string) queue = ({ }); //Commands waiting to be sent, and callbacks

	protected void create() {
		array ips = gethostbyname(server); //TODO: Support IPv6
		if (!ips || !sizeof(ips[1])) error("Unable to gethostbyname for %O\n", server);
		ip = random(ips[1]);
		sock->open_socket();
		sock->set_nonblocking(readable, connected, connfailed);
		sock->connect(ip, port); //Will throw on error
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

object connect(string module, string username, mapping options) {
	//If there's no existing connection, establish one.
	//If there is one, poke it?
}
