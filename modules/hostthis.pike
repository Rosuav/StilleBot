inherit command;

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

void create()
{
	if (!G->G->hostthis) G->G->hostthis = ([]);
	register_hook("channel-offline", gone);
}
