inherit command;
//TODO: Allow non-mods to add quotes, but they get saved as "pending". The one
//most recent pending quote can be permasaved by any mod with a simple command.
constant require_moderator = 1;
constant docstring = #"
Add a channel quote

Usage: `!addquote \"Something funny\" -- person` or 
`!addquote person Something funny`

Record those funny moments when amazing things happen. The quote is
automatically timestamped and gets the current stream category recorded.
Anyone can view these quotes with the [!quote](quote) command.
";

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Try '!addquote Something someone said -- person'";
	if (!channel->config->quotes) channel->config->quotes = ({ });
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return "@$$: Internal error - no channel info"; //I'm pretty sure this shouldn't happen
	//If you type "!addquote personname text", transform it.
	int simulate = sscanf(param, "-n %s", param);
	if (sscanf(param, "%*[@]%s %s", string who, string what) && what)
	{
		if (lower_case(who) == channel->name[1..] || channel->viewers[lower_case(who)])
		{
			//Seems to be a person's name at the start. Flip it to the end.
			//Note that this isn't perfect; if the person happens to not be in
			//the viewer list, the transformation won't work.
			//TODO: Check if there's an emote at either end of the 'what' and
			//add a space between that and the quote. Will need the tags from
			//the incoming message (not just 'string param').
			param = sprintf("\"%s\" -- %s", what, who);
		}
	}
	if (simulate)
		//For testing, just simulate adding the quote and displaying it
		return sprintf("@$$: SimQuote #%d: %s [%s]",
			sizeof(channel->config->quotes) + 1, param, chaninfo->game);
	channel->config->quotes += ({([
		"msg": param,
		"game": chaninfo->game,
		"mature": chaninfo->mature,
		"timestamp": time(),
	])});
	persist_config->save();
	return "@$$: Added quote #" + sizeof(channel->config->quotes);
}
