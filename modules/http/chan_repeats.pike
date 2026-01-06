//NOTE: This page has never really grown much, and is really just a table showing all
//of your autocommands. Could easily be folded into a subpage within /c/commands (eg
//in a dialog). Then /c/pointsrewards can be renamed to the much better /c/rewards,
//leaving /c/pointsrewards as a simple redirect, and I don't mind if there's a redirect
//that has a two-letter collision (here with /c/polls).
inherit http_websocket;

//TODO: Sort commands in some useful way?? Maybe by frequency?
//Currently I think they're sorted affabeck by command name.

constant markdown = #"# Automated commands for $$channel$$

Specify the time as `50-60` to mean a random range of times, or as `14:40` to mean that
exact time (in your timezone). Automated commands will be sent only if the channel is
online at that time.

Command | Frequency | Output |
--------|-----------|--------|-
loading... | - | - | -
{: #commandview}

[Save changes](:#savechanges)

Autocommands can either display text, or execute a command. It's usually easiest to tie
each autocommand to an [echo command](commands).

<style>
table {width: 100%;}
th, td:not(.wrap) {width: max-content; white-space: nowrap;}
th:nth-of-type(3), th:nth-of-type(3) {width: 100%;}
code {overflow-wrap: anywhere;}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return redirect("commands");
	return render(req, ([
		"vars": (["ws_type": "chan_commands", "ws_group": "", "ws_code": "chan_repeats"]),
	]) | req->misc->chaninfo);
}
