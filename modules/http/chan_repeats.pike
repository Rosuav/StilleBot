inherit http_websocket;

//TODO: Sort commands in some useful way?? Maybe by frequency?
//Currently I think they're sorted affabeck by command name.

//This page is now the place to put any repeat-related configs, eg (if I ever
//implement it, of course) "don't autocommand unless chat within last X seconds"

constant markdown = #"# Automated commands for $$channel$$

Specify the time as `50-60` to mean a random range of times, or as `14:40` to mean that
exact time (in your timezone). Automated commands will be sent only if the channel is
online at that time.

Command | Frequency | Output |
--------|-----------|--------|-
loading... | - | - | -
{: #commandview}

[Save changes](:#savechanges)

Create new autocommands with [!repeat](https://rosuav.github.io/StilleBot/commands/repeat)
and remove them with [!unrepeat](https://rosuav.github.io/StilleBot/commands/repeat).
Autocommands can either display text, or execute a command. It's usually easiest to tie
each autocommand to an [echo command](commands).

<style>
table {width: 100%;}
th, td:not(.wrap) {width: max-content; white-space: nowrap;}
th:nth-of-type(3), th:nth-of-type(3) {width: 100%;}
code {overflow-wrap: anywhere;}
</style>
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return redirect("commands");
	return render(req, ([
		"vars": (["ws_type": "chan_commands", "ws_group": "", "ws_code": "chan_repeats"])
			| G->G->command_editor_vars(req->misc->channel),
	]) | req->misc->chaninfo);
}
