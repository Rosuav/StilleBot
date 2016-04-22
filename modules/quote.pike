inherit command;
constant require_allcmds = 1;

string process(object channel, object person, string param)
{
	array quotes = channel->config->quotes;
	if (!quotes) return 0; //Ignore !quote when there are no quotes saved
	if (param == "0" || param == "count") return "@$$: There are "+sizeof(quotes)+" quotes recorded.";
	//TODO: Show mature quotes only if the requesting channel is also marked mature
	int idx = (int)param;
	if (param == "") idx = random(sizeof(quotes)) + 1;
	else if (idx <= 0 || idx > sizeof(quotes)) return "@$$: No such quote.";
	mapping quote = quotes[idx-1];
	return sprintf("@$$: Quote #%d: %s [%s]", idx, quote->msg, quote->game);
}

