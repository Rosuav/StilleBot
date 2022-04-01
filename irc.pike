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

object connect(string module, string username, string pass, mapping options) {
	//If there's no existing connection, establish one.
	//If there is one, poke it?
}
