inherit command;
constant require_allcmds = 1;

string process(object channel, object person, string param)
{
	array quotes = channel->config->quotes;
	if (!quotes) return 0; //Ignore !quote when there are no quotes saved
	//For safety, we show mature quotes only if the requesting channel is also marked mature.
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return "@$$: Internal error - no channel info"; //I'm pretty sure this shouldn't happen
	if (param == "0" || param == "count") return "@$$: There are "+sizeof(quotes)+" quotes recorded.";
	int idx = (int)param;
	if (param == "")
	{
		if (!sizeof(quotes)) return "@$$: No quotes recorded.";
		if (!chaninfo->mature)
		{
			//Pick a random non-mature quote, if available.
			array(int) safequotes = ({ });
			foreach (quotes; int i; mapping q)
				if (!q->mature) safequotes += ({i});
			if (!sizeof(safequotes)) return "@$$: All this channel's quotes are for mature audiences, sorry!";
			idx = random(safequotes) + 1;
		}
		else idx = random(sizeof(quotes)) + 1;
	}
	else if (idx <= 0 || idx > sizeof(quotes)) return "@$$: No such quote.";
	mapping quote = quotes[idx-1];
	return sprintf("@$$: Quote #%d: %s [%s]", idx, quote->msg, quote->game);
}

