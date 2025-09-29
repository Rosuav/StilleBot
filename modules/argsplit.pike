inherit builtin_command;

constant builtin_description = "Split an argument list into words";
constant builtin_name = "Arg Split";
constant builtin_param = ({"Parameter list eg {param}", "Max args (optional)"});
constant vars_provided = ([
	"{argc}": "Number of arguments (good for comparisons)",
	//Note that {arg0} in a Unix context would be the program name, so in this
	//case would be the command name. We don't have that, but it's still better
	//to start with arg1, despite array indexing starting from zero. It's also
	//easier for humans to think this way.
	"{arg1}": "First blank-delimited argument",
	"{arg2}": "Second blank-delimited argument",
	"{arg3}": "Third blank-delimited argument if present (etc)",
]);

mapping message_params(object channel, mapping person, array params) {
	array args = Process.split_quoted_string(params[0]);
	int maxargs = sizeof(params) > 1 && (int)params[1];
	if (maxargs < sizeof(args))
		args = args[..maxargs-2] + ({args[maxargs-1..] * " "});
	mapping ret = (["{argc}": ""+sizeof(args)]);
	foreach (args; int i; string arg) ret[sprintf("{arg%d}", i + 1)] = arg;
	return ret;
}
