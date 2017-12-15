inherit command;
constant require_moderator = 1;

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Try '!addquote Something someone said -- person'";
	if (!channel->config->quotes) channel->config->quotes = ({ });
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return "@$$: Internal error - no channel info"; //I'm pretty sure this shouldn't happen
	channel->config->quotes += ({([
		"msg": param,
		"game": chaninfo->game,
		"mature": chaninfo->mature,
		"timestamp": time(),
	])});
	persist->save();
	return "@$$: Added quote #" + sizeof(channel->config->quotes);
}
