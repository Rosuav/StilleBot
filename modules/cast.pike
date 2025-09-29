inherit builtin_command;

//Should this also offer a floatification?
constant builtin_description = "Find a number in something";
constant builtin_name = "Intify";
constant builtin_param = "Value";
constant vars_provided = ([
	"{value}": "Resulting numeric value",
]);

mapping message_params(object channel, mapping person, array params) {
	return (["{value}": (string)(int)params[0]]);
}
