inherit command;
constant featurename = "quotes";
constant docstring = #"
View a chosen or randomly-selected quote

Pick a random quote with `!quote`, or call up one in particular by giving its
reference number, such as `!quote 42`. Quotes are per-channel and any mod can
add more quotes, so when funny things happen, use the [!addquote](addquote)
command to save it for posterity!
";

echoable_message process(object channel, object person, string param)
{
	array quotes = channel->config->quotes;
	if (!quotes) return 0; //Ignore !quote when there are no quotes saved
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return "@$$: Internal error - no channel info"; //I'm pretty sure this shouldn't happen
	if (param == "0" || param == "count") return "@$$: There are "+sizeof(quotes)+" quotes recorded.";
	int idx = (int)param;
	if (param == "")
	{
		if (!sizeof(quotes)) return "@$$: No quotes recorded.";
		idx = random(sizeof(quotes)) + 1;
	}
	else if (idx <= 0 || idx > sizeof(quotes)) return "@$$: No such quote.";
	mapping quote = quotes[idx-1];
	object ts = Calendar.Gregorian.Second("unix", quote->timestamp);
	if (string tz = channel->config->timezone) ts = ts->set_timezone(tz) || ts;
	string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
	return sprintf("@$$: Quote #%d: %s [%s, %s]", idx, quote->msg, quote->game || "uncategorized", date);
}
