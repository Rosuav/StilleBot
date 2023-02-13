inherit http_websocket;
//TODO: Check for multi-response commands and show them better, esp in nonmod view
//TODO: List all automated commands for this channel (iterate over G->G->echocommands),
//showing their repeat rates or target times, and either having a gear button to open
//the command editor, or at very least, a link that opens ./commands#commandname in a
//new tab/window.

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
	mapping ac = req->misc->channel->config->autocommands;
	if (ac && sizeof(ac)) {
		//Migrate old autocommands to echocommands with automation
		string chan = req->misc->channel->name;
		foreach (ac; string cmd; array automate) {
			echoable_message command = G->G->echocommands[cmd[1..] + chan];
			if (!command && !has_prefix(cmd, "!")) {
				//Plain text in the automation table; synthesize a command.
				command = (["message": command, "access": "none"]);
				for (int i = 1; G->G->echocommands[(cmd = "auto" + i) + chan]; ++i) ;
			}
			G->G->update_command(req->misc->channel, "", replace(cmd, "!", ""), command | (["automate": automate]));
		}
		m_delete(req->misc->channel->config, "autocommands");
		persist_config->save();
	}
	return render(req, ([
		"vars": (["ws_type": "chan_commands", "ws_group": "", "ws_code": "chan_repeats",
			"complex_templates": G->G->commands_complex_templates, "builtins": G->G->commands_builtins,
			"pointsrewards": G->G->pointsrewards[req->misc->channel->name[1..]] || ({ }),
			"voices": req->misc->channel->config->voices || ([]),
		]),
	]) | req->misc->chaninfo);
}
