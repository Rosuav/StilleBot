//Implements !currency, but normally you'll execute this as !<currency-name>
//For example, in Rosuav's channel, the currency is "chocolates", so !chocolates
//will invoke this command.
inherit command;

void process(object channel, object person, string param)
{
	if (!channel->wealth) return;
	if (param == "help")
	{
		string offline = "";
		if (int ofl = channel->config->payout_offline)
			offline = sprintf(" while the channel is online, or every %s while offline",
				describe_time(channel->config->payout * ofl));
		//Note that the mod bonus isn't mentioned in "!currency help".
		send_message(channel->name, sprintf("@%s: Earn %s by hanging out in chat! You earn one every %s%s.",
			person->nick, channel->config->currency, describe_time(channel->config->payout), offline));
		return;
	}
	send_message(channel->name, sprintf("@%s: You have been with the stream for %s, and have earned %d %s.",
			person->nick, describe_time(channel->viewertime[person->user]),
			channel->wealth[person->user][0], channel->config->currency));
}
