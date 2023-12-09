//Eventually this will be folded into the core, but for now, it's a
//stand-alone script that just parses and synthesizes MustardScript.

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("mustard.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

constant oper_fwd = ([
	"==": "string",
	"in": "contains",
	"=~": "regexp",
	"-=": "spend",
]);
mapping oper_rev = mkmapping(values(oper_fwd), indices(oper_fwd));

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
mixed taketwo(mixed ignore, mixed take) {return take;}
mapping conditional(string kwd, mapping cond, mixed if_true, mixed maybeelse) {
	cond->message = if_true;
	if (maybeelse) cond->otherwise = maybeelse;
	return cond;
}
mapping cond(mapping flg, string expr1, string oper, string expr2, mapping flg2) {
	flg |= flg2;
	flg->expr1 = expr1;
	flg->expr2 = expr2;
	flg->conditional = oper_fwd[oper]; //If bad operator, will be unconditional. Should be caught by the grammar though.
	return flg;
}
mapping cond_calc(string expr1) {return (["conditional": "number", "expr1": expr1]);}
mapping cd_naked(string delay) {return (["conditional": "cooldown", "cdlength": (int)delay]);}
mapping cd_flags(string open, mapping flg, string delay, mapping flg2, string close) {
	return flg | flg2 | (["conditional": "cooldown", "cdlength": (int)delay]);
}
string emptymessage() {return "";}
mapping trycatch(string kwd, mixed message, string kwd2, mixed otherwise) {
	return (["conditional": "catch", "message": message, "otherwise": otherwise]);
}

constant KEYWORDS = (<"if", "else", "in", "test", "try", "catch", "cooldown">);

mixed /* echoable_message */ parse_mustard(string mustard) {
	//parser->set_error_handler(throw_errors);
	array|string next() {
		sscanf(mustard, "%*[ \t\r\n;]%s", mustard);
		if (mustard == "") return "";
		sscanf(mustard, "%[=,~-]%s", string token, mustard); //All characters that can be part of multi-character tokens
		if (token != "") return token;
		if (mustard[0] == '"' && sscanf(mustard, "%O%s", token, mustard)) return ({"string", token}); //String literal
		sscanf(mustard, "%[a-zA-Z0-9_]%s", token, mustard);
		if (token != "") {
			if (KEYWORDS[token]) return token;
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

/***** Temporarily duplicated from cmdmgr.pike *****/
constant message_flags = ([
	"mode": (<"random", "rotate", "foreach">),
	"dest": (<"/w", "/web", "/set", "/chain", "/reply", "//">),
]);
/***** End duplicated *****/
string quoted_string(string value) {
	return Standards.JSON.encode(value);
}
string atom(string value) {
	//TODO: If it's a valid atom, return it as-is
	return quoted_string(value);
}

void _make_mustard(mixed /* echoable_message */ message, Stdio.Buffer out, mapping state, int|void skipblock) {
	if (!message) return;
	if (stringp(message)) {out->sprintf("%s%s\n", state->indent * state->indentlevel, quoted_string(message)); return;}
	if (arrayp(message)) {
		if (!skipblock) out->sprintf("%s{\n", state->indent * state->indentlevel++);
		_make_mustard(message[*], out, state);
		if (!skipblock) out->sprintf("%s}\n", state->indent * --state->indentlevel);
		return;
	}
	int block = 0;
	void ensure_block() {
		if (block) return;
		out->sprintf("%s{\n", state->indent * state->indentlevel++);
		block = 1;
	}
	foreach (message_flags; string flg;) if (message[flg]) {
		ensure_block();
		out->sprintf("%s#%s = %s\n", state->indent * state->indentlevel, flg, atom(message[flg]));
	}
	if (message->builtin) {
		string params = "";
		if (arrayp(message->builtin_param)) params = quoted_string(message->builtin_param[*]) * ", ";
		if (stringp(message->builtin_param)) params = quoted_string(message->builtin_param);
		out->sprintf("%s%s(%s)", state->indent * state->indentlevel, message->builtin, params);
		mixed msg = message->message || "";
		if (stringp(msg)) {out->sprintf(" %s\n", quoted_string(msg)); return;}
		else if (arrayp(msg)) {
			out->add(" {\n");
			++state->indentlevel;
			_make_mustard(msg, out, state, 1);
			out->sprintf("%s}\n", state->indent * --state->indentlevel);
			return;
		}
		else out->add(" {\n");
		block = 1; ++state->indentlevel;
	}
	if (message->conditional == "catch") {
		out->sprintf("%stry", state->indent * state->indentlevel);
		mixed msg = message->message || "";
		if (stringp(msg)) out->sprintf(" %s\n", quoted_string(msg));
		else {
			out->add(" {\n");
			++state->indentlevel;
			_make_mustard(msg, out, state, 1);
			out->sprintf("%s}\n", state->indent * --state->indentlevel);
		}
		out->sprintf("%scatch", state->indent * state->indentlevel);
		msg = message->otherwise || ""; //Should this "compact if possible" bit become a function?
		if (stringp(msg)) out->sprintf(" %s\n", quoted_string(msg));
		else {
			out->add(" {\n");
			++state->indentlevel;
			_make_mustard(msg, out, state, 1);
			out->sprintf("%s}\n", state->indent * --state->indentlevel);
		}
	}
	else if (message->conditional) {
		//FIXME: All of these need their flags added. Before or after the main condition? Both are legal.
		if (message->conditional == "number")
			out->sprintf("%stest (%s) {\n", state->indent * state->indentlevel++, quoted_string(message->expr1));
		else if (message->conditional == "cooldown")
			out->sprintf("%scooldown (%s) {\n", state->indent * state->indentlevel++, (string)message->delay);
		else if (string oper = oper_rev[message->conditional])
			out->sprintf("%sif (%s %s %s) {\n", state->indent * state->indentlevel++, quoted_string(message->expr1 || ""), oper, quoted_string(message->expr2 || ""));
		else error("Unrecognized conditional type %O\n", message->conditional);
		_make_mustard(message->message || "", out, state, 1); //Gotta have the if branch
		out->sprintf("%s}\n", state->indent * --state->indentlevel);
		//NOTE: Omitting the else is currently disallowed, but I intend to make the grammar more flexible later.
		/* if (message->otherwise) */ { //Omitting both the else and its block is legal, and in a lot of cases, will be sufficient (most cooldowns don't need an else)
			out->sprintf("%selse {\n", state->indent * state->indentlevel++);
			_make_mustard(message->otherwise, out, state, 1);
			out->sprintf("%s}\n", state->indent * --state->indentlevel);
		}
	}
	else _make_mustard(message->message, out, state);
	if (block) out->sprintf("%s}\n", state->indent * --state->indentlevel);
}

string make_mustard(mixed /* echoable_message */ message) {
	mapping state = (["indent": "    ", "indentlevel": 0]);
	Stdio.Buffer out = Stdio.Buffer();
	if (mappingp(message)) foreach ("access visibility aliases redemption" / " ", string flg) {
		if (message[flg]) out->sprintf("#%s = %s\n", flg, atom(message[flg]));
	}
	//TODO: message->automate
	_make_mustard(message, out, state);
	return (string)out;
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
		if (has_suffix(arg, ".json")) {
			mixed data = Standards.JSON.decode_utf8(Stdio.read_file(arg));
			if (mappingp(data) && data->commands) {
				parser->set_error_handler(throw_errors);
				//Round-trip testing of an entire channel's commands
				foreach (sort(indices(data->commands)), string cmd) if (mixed ex = catch {
					string code = make_mustard(data->commands[cmd]);
					mixed parsed = parse_mustard(code);
					//TODO: Compare (may require some bot infrastructure for cmdmgr)
					write("%s:%s: passed\n", arg, cmd);
				}) write("%s:%s: %s\n", arg, cmd, describe_error(ex));
			} else write("%s\n\n", make_mustard(data));
		}
		else if (sscanf(arg, "%s.json:%s", string fn, string cmd) && cmd) {
			mixed data = Standards.JSON.decode_utf8(Stdio.read_file(fn + ".json"))->commands[cmd];
			string code = make_mustard(data);
			write("%s\n\n", code);
			write("Parse-back: %O\n", parse_mustard(code));
		}
		else write("Result: %O\n", parse_mustard(Stdio.read_file(arg)));
	}
}
