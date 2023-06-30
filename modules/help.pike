inherit command;
constant featurename = "info";
constant docstring = #"
List commands available to you

This command will list every command that you have permission to use in the
channel you are in, apart from hidden commands.

You can also use \"!help !somecommand\" to get additional information on any
command.
";

echoable_message process(object channel, mapping person, string param)
{
	multiset(string) cmds = (<>);
	int is_mod = G->G->user_mod_status[person->user + channel->name];
	if (param != "")
	{
		//NOTE: We say "mod-only" if a mod command comes up when a non-mod one
		//doesn't, even if that's not quite the case. There could be edge cases.
		sscanf(param, "%*[ !]%s%*[ ]", param);
		string modonly = "";
		echoable_message cmd = find_command(channel, param, 0);
		if (!cmd) {cmd = find_command(channel, param, 1); modonly = " mod-only";}
		if (!cmd) return "@$$: That isn't a command in this channel, so far as I can tell.";
		if (!functionp(cmd))
		{
			//Do I need any more info? Maybe check if it's a mapping to see if it has a dest?
			return sprintf("@$$: !%s is an echo command - see https://rosuav.github.io/StilleBot/commands/addcmd", param);
		}
		object obj = function_object(cmd);
		string pgm = sprintf("%O", object_program(obj)) - ".pike"; //For some reason function_name isn't giving me the right result (??)
		int hidden = obj->hidden_command || obj->visibility == "hidden";
		return sprintf("@$$: !%s is a%s%s%s command.%s", param,
			!obj->docstring ? "n undocumented ": "",
			hidden ? " hidden": "",
			modonly,
			obj->docstring && !hidden ? " Learn more at https://rosuav.github.io/StilleBot/commands/" + pgm : "",
		);
	}
	foreach (({G->G->commands, G->G->echocommands}), mapping commands)
		foreach (commands; string cmd; command_handler handler)
		{
			object|mapping flags =
				//Availability flags come from the providing object for coded functions.
				functionp(handler) ? function_object(handler) :
				//Those with their own flags use those. Otherwise assume all defaults.
				mappingp(handler) ? handler : ([]);
			if (flags->hidden_command || flags->visibility == "hidden") continue;
			if (flags->featurename && !channel->config->features[?flags->featurename]) return 0;
			if ((flags->require_moderator || flags->access == "mod") && !is_mod) continue;
			if (flags->access == "none") continue;
			if (has_prefix(cmd, "!")) continue; //Special responses aren't commands
			if (!has_value(cmd, '#') || has_suffix(cmd, channel->name))
				cmds[cmd - channel->name] = 1;
		}
	string local_info = "";
	if (string addr = persist_config["ircsettings"]->http_address)
		local_info = " You can also view further information about this specific channel at " + addr + "/channels/" + channel->name[1..];
	return ({"@$$: Available commands are: " + ("!"+sort(indices(cmds))[*]) * " ",
		"For additional information, see https://rosuav.github.io/StilleBot/commands/" + local_info});
}
