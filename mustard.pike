//Eventually this will be folded into the core, but for now, it's a
//stand-alone script that just parses and synthesizes MustardScript.

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("mustard.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

mapping makeflags() {return ([]);}
mapping addflag(mapping flg, string hash, string name, string eq, string val) {flg[name] = val; return flg;}
mapping flagmessage(mapping flg, mixed message) {flg->message = message; return flg;}
mapping flagmessage2(string open, mapping flg, mixed message, string close) {flg->message = message; return flg;}
mapping builtin(string name, string open, array params, string close, mixed message) {
	return (["builtin": name, "builtin_param": params, "message": message]);
}
array gather(mixed elem, array arr) {return ({elem}) + arr;}
array makeparams(string|void param) {return param ? ({param}) : ({ });}
array addparam(array params, string comma, string param) {return params + ({param});}
mapping makecomment(string comment) {return (["dest": "//", "message": comment]);}

mixed /* echoable_message */ parse_mustard(string mustard) {
	//parser->set_error_handler(throw_errors);
	array|string next() {
		sscanf(mustard, "%*[ \t\r\n;]%s", mustard);
		if (mustard == "") return "";
		sscanf(mustard, "%[=,]%s", string token, mustard); //All characters that can be part of multi-character tokens
		if (token != "") return token;
		if (mustard[0] == '"' && sscanf(mustard, "%O%s", token, mustard)) return ({"string", token}); //String literal
		sscanf(mustard, "%[a-zA-Z0-9_]%s", token, mustard);
		if (token != "") {
			//A number has nothing but digits, but a name can't start
			//with a digit. So it's an error to have eg 123AB4.
			if (token[0] >= '0' && token[0] <= '9') {
				[int min, int max] = String.range(token);
				if (min >= '0' && max <= '9') return ({"number", token});
				error("Names may not start with digits\n");
			}
			return ({"name", token});
		}
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
	//QUIRK: An action attached to a rule with no symbols (eg "flags: {makeflags};") is
	//interpreted as a callable string instead of a lookup into the action object. So we
	//redefine it.
	foreach (parser->grammar; int state; array rules) {
		foreach (rules, object rule) {
			if (!sizeof(rule->symbols) && stringp(rule->action))
				rule->action = this[rule->action];
		}
	}
	if (argc < 2) exit(0, "USAGE: pike %s fn [fn [fn...]]\n");
	foreach (argv[1..], string arg) {
		if (has_suffix(arg, ".json")) ; //TODO: Load JSON and emit MustardScript
		else write("Result: %O\n", parse_mustard(Stdio.read_file(arg)));
	}
}
