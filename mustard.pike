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
mapping conditional(string kwd, mapping cond, mixed if_true, mixed maybeelse, mixed if_false) {
	cond->message = if_true;
	cond->otherwise = if_false;
	return cond;
}
mapping cond(mapping flg, string expr1, string oper, string expr2) {
	flg->expr1 = expr1;
	flg->expr2 = expr2;
	flg->conditional = oper_fwd[oper]; //If bad operator, will be unconditional. Should be caught by the grammar though.
	return flg;
}
mapping cond_calc(string expr1) {return (["conditional": "number", "expr1": expr1]);}

constant KEYWORDS = (<"if", "else", "in", "test">);

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
string atom(string value) {
	//TODO: If it's a valid atom, return it as-is
	return sprintf("%q", value);
}

void _make_mustard(mixed /* echoable_message */ message, Stdio.Buffer out, mapping state) {
	if (!message) return;
	if (stringp(message)) {out->sprintf("%s%q\n", state->indent * state->indentlevel, message); return;}
	if (arrayp(message)) {
		out->sprintf("%s{\n", state->indent * state->indentlevel++);
		_make_mustard(message[*], out, state);
		out->sprintf("%s}\n", state->indent * --state->indentlevel);
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
		if (arrayp(message->builtin_param)) params = sprintf("%q", message->builtin_param[*]) * ", ";
		if (stringp(message->builtin_param)) params = sprintf("%q", message->builtin_param);
		out->sprintf("%s%s(%s)\n", state->indent * state->indentlevel, message->builtin, params);
		//TODO: Emit a block on the same line, or a single message indented on the next line
	}
	if (message->conditional) {
		if (message->conditional == "number")
			out->sprintf("%stest (%q) {\n", state->indent * state->indentlevel++, message->expr1);
		else out->sprintf("%sif (%q %s %q) {\n", state->indent * state->indentlevel++, message->expr1 || "", oper_rev[message->conditional], message->expr2 || "");
		_make_mustard(message->message || "", out, state); //Gotta have the if branch
		out->sprintf("%s}\n", state->indent * --state->indentlevel);
		if (message->otherwise) {
			out->sprintf("%selse {\n", state->indent * state->indentlevel++);
			_make_mustard(message->otherwise, out, state);
			out->sprintf("%s}\n", state->indent * --state->indentlevel);
		}
	}
	else _make_mustard(message->message, out, state);
	if (block) out->sprintf("%s}\n", state->indent * --state->indentlevel);
}

string make_mustard(mixed /* echoable_message */ message) {
	mapping state = (["indent": "    ", "indentlevel": 0]);
	Stdio.Buffer out = Stdio.Buffer();
	foreach ("access visibility aliases redemption" / " ", string flg) {
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
		if (has_suffix(arg, ".json")) write("%s\n\n", make_mustard(Standards.JSON.decode_utf8(Stdio.read_file(arg))));
		else write("Result: %O\n", parse_mustard(Stdio.read_file(arg)));
	}
}