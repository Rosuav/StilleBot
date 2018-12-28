inherit command;
constant require_moderator = 1;
//TODO-DOCSTRING

echoable_message process(object channel, object person, string param)
{
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
