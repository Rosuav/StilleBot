inherit command;
constant require_allcmds = 1;
constant require_moderator = 1;

string process(object channel, object person, string param)
{
	if (!channel->config->quotes) channel->config->quotes = ({ });
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	channel->config->quotes += ({([
		"msg": param,
		"game": chaninfo->game,
		"mature": chaninfo->mature,
		"timestamp": time(),
	])});
	persist->save();
	return "@$$: Added quote #" + sizeof(channel->config->quotes);
}

