inherit command;
constant featurename = "quotes";
constant require_moderator = 1;
constant docstring = #"
Delete a channel quote

Usage: `!delquote 123`

Remove a quote added with the `!addquote` command. Note that this will
renumber all quotes after the one removed.
";

echoable_message process(object channel, object person, string param)
{
	if (channel->config->disable_quotes) return 0;
	if (param == "") return "";
	if (!channel->config->quotes) return "";
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return "@$$: Internal error - no channel info"; //I'm pretty sure this shouldn't happen
	int idx = (int)param;
	if (!idx || idx > sizeof(channel->config->quotes)) return "@$$: No such quote.";
	channel->config->quotes[idx - 1] = 0;
	channel->config->quotes -= ({0});
	persist_config->save();
	return "@$$: Removed quote #" + idx;
}
