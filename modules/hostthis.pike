inherit command;
constant featurename = 0;
constant hidden_command = 1;

//TODO: Only gone them if the last hostthis by that person was this channel.
int gone(string channel)
{
	foreach (m_delete(G->G->hostthis, channel) || ({ }), string person)
		send_message("#" + person, "/unhost");
}

string process(object channel, object person, string param)
{
	send_message("#"+person->nick, "/host "+channel->name[1..]);
	G->G->hostthis[channel->name[1..]] += ({person->nick});
}

protected void create(string name)
{
	if (!G->G->hostthis) G->G->hostthis = ([]);
	register_hook("channel-offline", gone);
	::create(name);
}
