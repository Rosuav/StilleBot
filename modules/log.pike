//Slated for removal.
inherit builtin_command;

constant builtin_description = "Log to a file - DEPRECATED. Use 'Log Error' instead.";
constant builtin_name = "Log to file (deprecated)";
constant builtin_param = "Info";
constant vars_provided = ([]);
mapping message_params(object channel, mapping person, array params) {
	Stdio.append_file("cmd_notes.log", sprintf("[%s %s] %s\n", channel->name, ctime(time())[..<1], params[0]));
	return ([]);
}
