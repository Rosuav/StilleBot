inherit builtin_command;

constant builtin_description = "Log to a file";
constant builtin_name = "Log to file";
constant builtin_param = "Info";
constant vars_provided = ([]);
mapping message_params(object channel, mapping person, string param) {
	Stdio.append_file("cmd_notes.log", sprintf("[%s %s] %s\n", channel->name, ctime(time())[..<1], param));
	return ([]);
}
