inherit command;
constant featurename = "commands";
constant require_moderator = 1;
constant docstring = #"
Configure an echo command for this channel

Usage: `!setcmd !commandname option [option [option...]]`

Options not specified remain as they are. Newly-created commands have the
first of each group by default.

Group       | Option     | Effect
------------+------------+----------
Multi-text  | sequential | Multiple responses will be given in order as a chained response.
            | random     | Where multiple responses are available, pick one at random.
Destination | chat       | Send the response in the chat channel that the command was given.
            | whisper    | Whisper the response to the person who gave the command.
            | wtarget    | Whisper the response to the target named in the command.
Access      | anyone     | Anyone can use the command
            | modonly    | Only moderators (and broadcaster) may use the command.
            | vipmod     | Only mods/VIPs (and broadcaster) may use the command.
Visibility  | visible    | Command will be listed in !help
            | hidden     | Command will be unlisted

Editing commands can also be done via the bot's web browser configuration
pages, where available.
";

string process(object channel, object person, string param)
{
	if (sscanf(param, "!%[^# ] %s", string cmd, string flags) == 2)
	{
		//Create a new command. Note that it *always* gets the channel name appended,
		//making it a channel-specific command; global commands can only be created by
		//manually editing the JSON file.
		cmd = command_casefold(cmd);
		//These flags don't apply to the addcmd specials
		if (has_value(cmd, '!')) return "@$$: Command names cannot include exclamation marks";
		echoable_message command = channel->commands[cmd];
		if (!command) return "@$$: Command " + cmd + " not found (only echo commands can be configured).";
		if (!mappingp(command)) command = (["message": command]);
		else command = command | ([]); //Prevent accidental mutation
		
		foreach (flags / " ", string flag) switch (flag)
		{
			case "sequential": m_delete(command, "mode"); break;
			case "random": command->mode = "random"; break;
			case "chat": m_delete(command, "dest"); m_delete(command, "target"); break;
			case "whisper": command->dest = "/w"; command->target = "$$"; break;
			case "wtarget": command->dest = "/w"; command->target = "%s"; break;
			case "anyone": m_delete(command, "access"); break;
			case "modonly": command->access = "mod"; break;
			case "vipmod": command->access = "vip"; break;
			case "disabled": command->access = "none"; break;
			case "visible": m_delete(command, "visibility"); break;
			case "hidden": command->visibility = "hidden"; break;
			default: return "@$$: Unknown option " + flag; //Won't update the command
		}
		if (sizeof(command) == 1) command = command->message; //No unnecessary mappings
		make_echocommand(cmd + channel->name, command);
		return sprintf("@$$: Updated command !%s", cmd);
	}
	return "@$$: Try !setcmd !cmdname option -- see https://rosuav.github.io/StilleBot/commands/setcmd";
}
