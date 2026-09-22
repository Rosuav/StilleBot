inherit builtin_command;

constant builtin_description = "Split an argument list into words";
constant builtin_name = "Arg Split";
constant builtin_param = ({"Parameter list eg {param}", "Max args (optional)"});
constant vars_provided = ([
	"{arg}": "Array of arguments",
	"{argc}": "Number of arguments (same as {arg.0})",
	//Note that {arg.0} in a Unix context would be the program name, so in this
	//case would be the command name. We don't have that, but it's still better
	//to start with arg.1, since humans think that way. Fortunately we can use
	//REXX-style arrays where {arg.0} is the number of elements.
	"{arg1}": "First blank-delimited argument, same as {arg.1}",
	"{arg2}": "Second argument, same as {arg.2}",
	"{arg3}": "Third if present (etc)",
]);

mapping message_params(object channel, mapping person, array params) {
	array args = Process.split_quoted_string(params[0]);
	int maxargs = sizeof(params) > 1 && (int)params[1];
	if (maxargs && maxargs < sizeof(args))
		args = args[..maxargs-2] + ({args[maxargs-1..] * " "});
	mapping ret = (["{argc}": ""+sizeof(args), "{arg}": args]);
	//For backward compatibility, provide the old {argN} individual strings.
	//New code should prefer {arg.N} array notation instead. At some point I
	//will de-document the individuals, but they'll continue to be provided
	//for a good while yet.
	foreach (args; int i; string arg) ret[sprintf("{arg%d}", i + 1)] = arg;
	return ret;
}
