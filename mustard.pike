//Eventually this will be folded into the core, but for now, it's a
//stand-alone script that just parses and synthesizes MustardScript.

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("mustard.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

mixed /* echoable_message */ parse_mustard(string mustard) {
	//parser->set_error_handler(throw_errors);
	array|string next() {
		sscanf(mustard, "%*[ \t\r\n;]%s", mustard);
		if (mustard == "") return "";
		sscanf(mustard, "%[=,]%s", string token, mustard); //All characters that can be part of multi-character tokens
		if (token != "") return token;
		sscanf(mustard, "%[a-zA-Z]%s", token, mustard);
		if (token != "") return ({"name", token});
		if (mustard[0] == '"' && sscanf(mustard, "%O%s", token, mustard)) return ({"string", token}); //String literal
		sscanf(mustard, "%[0-9]%s", token, mustard);
		if (token != "") return ({"number", token});
		sscanf(mustard, "//%[^\n]%s", token, mustard);
		if (token != "") return ({"comment", token});
		sscanf(mustard, "%1s%s", token, mustard); //Otherwise, grab a single character
		return token;
	}
	//array|string shownext() {array|string ret = next(); werror("TOKEN: %O\n", ret); return ret;}
	//while (shownext() != ""); return 0; //Dump tokens w/o parsing
	return parser->parse(next, this);
}

int main(int argc, array(string) argv) {
	if (argc < 2) exit(0, "USAGE: pike %s fn [fn [fn...]]\n");
	foreach (argv[1..], string arg) {
		if (has_suffix(arg, ".json")) ; //TODO: Load JSON and emit MustardScript
		else write("Result: %O\n", parse_mustard(Stdio.read_file(arg)));
	}
}
