#if constant(G)
inherit builtin_command;
#else
int main(int argc, array(string) argv) {
	mixed ex = catch {write("Result: %O\n", evaluate(argv[1..] * " "));};
	if (ex) write("Invalid expression: %s\n", (describe_error(ex) / "\n")[0]);
}
#endif

constant KEYWORDS = (<"x">);

//Define functions here that can be called in expressions
//Note that the function name (after the "func_" prefix) must match the sscanf
//in evaluate()'s inner tokenizer function.

int|float func_random(array(int|float) args) {
	if (sizeof(args) != 1) error("random() requires precisely one argument\n");
	//If it looks like an integer, return a random integer.
	if (args[0] == (int)args[0]) return random((int)args[0]);
	return random(args[0]); //Otherwise a float.
}

int|float func(mixed word, string open, array(int|float) args, string close) {
	word = word[0];
	function func = this["func_" + word];
	if (!func) error("Unknown function " + word + "\n");
	return func(args);
}
int|float func_nullary(mixed word, string open, string close) {return func(word, open, ({ }), close);}

int|float binop(int|float left, string op, int|float right) {
	switch (op) {
		#define BINARY(o) case #o: return left o right
		BINARY(+); BINARY(-); BINARY(*); BINARY(/); BINARY(%);
		BINARY(<); BINARY(<=); BINARY(==); BINARY(!=); BINARY(>=); BINARY(>);
		BINARY(&&); BINARY(||); BINARY(**);
		#undef BINARY
		//Some aliases for the convenience of humans
		//We won't have assignment here (or if we do, bring on the
		//walrus operator), nor bitwise operations, so it's nicer
		//to let people use these in other natural ways.
		case "=": return left == right;
		case "&": return left && right;
		case "|": return left || right;
		case "^": return left ** right;
		case "=>": return left >= right;
		case "x": return left * right;
	}
}

string stitch(string ... parts) {return parts * "";}
int makeint(string digits) {sscanf(digits, "%d", int ret); return ret;} //Always parse as decimal
float makefloat(string digits) {return (float)digits;}
int|float parens(string open, int|float val, string close) {return val;}
array(int|float) make_array(int|float val) {return ({val});}
array(int|float) prepend_array(int|float val, string _, array(int|float) arr) {return ({val}) + arr;}

//To allow variable lookups, bare words must be adorned with a context.
//Thus "@spam" will carry with it, at very least, the channel to which the
//variable belongs. Note that all use of variable lookups/assignments is
//undocumented and unstable, and should not be depended upon.
int|float|string varlookup(mixed ... args) {werror("VAR LOOKUP %O\n", args); return 42;}
int|float|string varassign(mixed ... args) {werror("VAR ASSIGN %O\n", args); return 278;} //Assignment returns the RHS.

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

int|float evaluate(string formula, mixed|void ctx) {
	parser->set_error_handler(throw_errors);
	array|string next() {
		if (formula == "") return "";
		sscanf(formula, "%*[ \t\n]%s", formula);
		sscanf(formula, "%[*&|<=>!]%s", string token, formula); //All characters that can be part of multi-character tokens
		if (token != "") return token;
		sscanf(formula, "%[a-zA-Z]%s", token, formula);
		if (KEYWORDS[token]) return token; //Special keywords are themselves and can't be function names.
		if (token != "") return ({"word", ({token, ctx})}); //Probably a function name.
		if (formula[0] == '"' && sscanf(formula, "%O%s", token, formula)) return ({"string", token}); //String literal
		sscanf(formula, "%1s%s", token, formula); //Otherwise, grab a single character
		return token;
	}
	//array|string shownext() {array|string ret = next(); werror("TOKEN: %O\n", ret); return ret;}
	return parser->parse(next, this);
}

constant builtin_description = "Perform arithmetic calculations";
constant builtin_name = "Calculator";
constant builtin_param = "Expression";
constant vars_provided = ([
	"{error}": "Blank if all is well, otherwise an error message",
	"{result}": "The result of the calculation",
]);
constant command_suggestions = (["!calc": ([
	"_description": "Calculate a simple numeric expression/formula",
	"builtin": "calc", "builtin_param": "%s",
	"message": ([
		"conditional": "string", "expr1": "{error}", "expr2": "",
		"message": "@$$: {result}",
		"otherwise": "@$$: {error}",
	]),
])]);
mapping message_params(object channel, mapping person, string param) {
	if (param == "") return (["{error}": "Usage: !calc 1+2", "{result}": ""]);
	if (person->badges->?_mod) param = channel->expand_variables(param);
	mixed ex = catch {
		int|float|string result = evaluate(param, channel);
		//"!calc 1.5 + 2.5" will give a result of 4.0, but it's nicer to say "4"
		if (floatp(result) && result == (float)(int)result) result = (int)result;
		return (["{error}": "", "{result}": sprintf("%O", result)]);
	};
	return (["{error}": "Invalid expression [" + (describe_error(ex)/"\n")[0] + "]", "{result}": ""]);
}

#if constant(G)
protected void create(string name) {::create(name); G->G->evaluate_expr = evaluate;}
#endif
