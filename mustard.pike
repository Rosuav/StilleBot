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
mapping addflag(mapping flg, string hash, string name, string val) {flg[name] = val; return flg;}
mapping addflag2(mapping flg, string hash, string name, string eq, string val) {flg[name] = val; return flg;}
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
	if (expr1 != "") flg->expr1 = expr1;
	if (expr2 != "") flg->expr2 = expr2;
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

mixed /* echoable_message */ parse_mustard(string|Stdio.Buffer mustard) {
	if (stringp(mustard)) mustard = Stdio.Buffer(string_to_utf8(mustard));
	mustard->read_only();
	//parser->set_error_handler(throw_errors);
	array|string next() {
		mustard->sscanf("%*[ \t\r\n;]");
		if (!sizeof(mustard)) return "";
		if (array token = mustard->sscanf("%[=,~-]")) //All characters that can be part of multi-character tokens
			return token[0];
		//In theory, this should do the job. Not sure why it doesn't work.
		//if (mustard[0] == '"') return ({"string", mustard->read_json()});
		//Instead, let's roll our own - or, since I already did, lift from
		//EU4Parser where I basically did the same thing.
		if (array str = mustard->sscanf("\"%[^\"]\"")) {
			//Fairly naive handling of backslashes and quotes. It might be better to do this more properly.
			string lit = str[0];
			while (lit != "" && lit[-1] == '\\') {
				str = mustard->sscanf("%[^\"]\"");
				if (!str) break; //Should possibly be a parse error?
				lit = lit[..<1] + "\"" + str[0];
			}
			return ({"string", utf8_to_string(replace(lit, (["\\\\": "\\", "\n": " "])))});
		}
		if (array tok = mustard->sscanf("%[a-zA-Z0-9_]")) {
			string token = tok[0];
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
		if (array token = mustard->sscanf("//%[^\n]")) return ({"comment", token[0]});
		return mustard->read(1); //Otherwise, grab a single character
	}
	//array|string shownext() {array|string ret = next(); werror("TOKEN: %O\n", ret); return ret;}
	//while (shownext() != ""); return 0; //Dump tokens w/o parsing
	return parser->parse(next, this);
}

constant message_flags = ({"delay", "dest", "target", "destcfg", "voice", "mode", "participant_activity"});
string quoted_string(string value) {
	return string_to_utf8(Standards.JSON.encode(value));
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
	if (message->dest == "//" && stringp(message->message)) {
		out->sprintf("%s//%s\n", state->indent * state->indentlevel, message->message);
		return;
	}
	int block = 0; //On initial build, we can skip ANY block, not just a safe one
	void ensure_block() {
		if (block || skipblock == 2) return;
		out->sprintf("%s{\n", state->indent * state->indentlevel++);
		block = 1;
	}
	foreach (message_flags, string flg) if (message[flg]) {
		ensure_block();
		out->sprintf("%s#%s %s\n", state->indent * state->indentlevel, flg, atom(message[flg]));
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
		else if (message->conditional == "cooldown") {
			string attrs = "";
			foreach (({"cdname", "cdqueue"}), string attr) if (message[attr])
				attrs = sprintf("%s #%s %s", attrs, attr, stringp(message[attr]) ? quoted_string(message[attr]) : (string)message[attr]);
			out->sprintf("%scooldown (%s%s) {\n", state->indent * state->indentlevel++, (string)message->cdlength, attrs);
		}
		else if (string oper = oper_rev[message->conditional]) {
			string attrs = "";
			foreach (({"casefold"}), string attr) if (message[attr])
				attrs = sprintf("%s #%s %s", attrs, attr, stringp(message[attr]) ? quoted_string(message[attr]) : (string)message[attr]);
			out->sprintf("%sif (%s %s %s%s) {\n", state->indent * state->indentlevel++, quoted_string(message->expr1 || ""), oper, quoted_string(message->expr2 || ""), attrs);
		}
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
	else _make_mustard(message->message, out, state, block || skipblock == 2);
	if (block) out->sprintf("%s}\n", state->indent * --state->indentlevel);
}

string make_mustard(mixed /* echoable_message */ message) {
	mapping state = (["indent": "    ", "indentlevel": 0]);
	Stdio.Buffer out = Stdio.Buffer();
	if (mappingp(message)) {
		foreach ("access visibility aliases redemption" / " ", string flg)
			if (message[flg]) out->sprintf("#%s %s\n", flg, atom(message[flg]));
		if (message->automate) out->sprintf("#automate %s\n", quoted_string(G->G->cmdmgr->automation_to_string(message->automate)));
	}
	_make_mustard(message, out, state, 2);
	return utf8_to_string((string)out);
}

//Invoke diff(1) with FDs 0 and 3 carrying the provided strings
//Returns 1 if there were any differences, 0 if identical (or any other return code from diff)
int diff(string old, string new) {
	object|zero fdold = Stdio.File();
	object|zero fdnew = Stdio.File();
	object proc = Process.Process(
		({"diff", "-u", "-", "/dev/fd/3"}),
		([
			"stdin": fdold->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE),
			"fds": ({fdnew->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE)}),
			"callback": lambda() {fdold = fdnew = 0;},
		]),
	);
	Pike.SmallBackend backend = Pike.SmallBackend();
	Shuffler.Shuffler shuf = Shuffler.Shuffler();
	shuf->set_backend(backend);
	Shuffler.Shuffle sfold = shuf->shuffle(fdold);
	sfold->add_source(old);
	sfold->set_done_callback() {fdold->close(); fdold = 0;};
	sfold->start();
	Shuffler.Shuffle sfnew = shuf->shuffle(fdnew);
	sfnew->add_source(new);
	sfnew->set_done_callback() {fdnew->close(); fdnew = 0;};
	sfnew->start();
	while (fdold || fdnew) backend(1.0);
	return proc->wait();
}

mixed validate(mixed response, string cmd) {
	mixed validated = G->G->cmdmgr->_validate_toplevel(response, (["cmd": cmd, "cooldowns": ([]), "retain_internal_names": 1]));
	if (cmd == "!trigger") {
		validated = Array.arrayify(validated); //Triggers are always in an array.
		//They also lack any 'otherwise' clause, since triggers are conditional inherently.
		foreach (validated, mixed trig) if (mappingp(trig)) m_delete(trig, "otherwise");
	}
	return validated;
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
	int quiet = 0;
	foreach (argv[1..], string arg) {
		if (arg == "-q") {quiet = 1; continue;}
		if (has_suffix(arg, ".json")) {
			mixed data = Standards.JSON.decode_utf8(Stdio.read_file(arg));
			if (mappingp(data) && data->login) {
				parser->set_error_handler(throw_errors);
				//Round-trip testing of an entire channel's commands
				foreach (sort(indices(data->commands || ({ }))), string cmd) if (mixed ex = catch {
					mixed orig = data->commands[cmd];
					string code = make_mustard(orig);
					mixed parsed = parse_mustard(code);
					//Test the parser:
					mixed validated = validate(parsed, cmd);
					//Or test the validation itself:
					//mixed validated = validate(orig, cmd);
					//For comparison purposes, hide the id attributes on triggers.
					if (cmd == "!trigger")
						foreach (orig, mixed trig)
							if (mappingp(trig)) m_delete(trig, "id");
					if (sprintf("%O", orig) == sprintf("%O", validated)) {
						if (!quiet) write("%s:%s: passed\n", arg, cmd);
					}
					else write("%4d %s:%s: Not identical\n", sizeof(sprintf("%O", orig)), arg, cmd);
				}) write("%s:%s: %s\n", arg, cmd, describe_error(ex));
			} else write("%s\n\n", string_to_utf8(make_mustard(data)));
		}
		else if (sscanf(arg, "%s.json:%s", string fn, string cmd) && cmd) {
			mapping data = Standards.JSON.decode_utf8(Stdio.read_file(fn + ".json"));
			write("Channel: %s\n", data->login);
			mixed orig = data->commands[cmd];
			string code = make_mustard(orig);
			write("%s\n\n", string_to_utf8(code));
			mixed parsed = parse_mustard(code);
			write("Parse-back: %O\n", parsed);
			//As above, test the parser:
			mixed validated = validate(parsed, cmd);
			//Or test the validation:
			//mixed validated = validate(orig, cmd);
			if (cmd == "!trigger")
				foreach (orig, mixed trig)
					if (mappingp(trig)) m_delete(trig, "id");
			write("Validated: %O\n", validated);
			if (!diff(sprintf("%O\n", orig), sprintf("%O\n", validated))) write("Identical!\n");
		}
		else {
			mixed parsed = parse_mustard(Stdio.read_file(arg));
			write("Parsed: %O\n", parsed);
			mixed validated = validate(parsed, parsed->command || "command");
			write("Validated: %O\n", validated);
		}
	}
}
