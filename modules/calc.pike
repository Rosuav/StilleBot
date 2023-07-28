#if constant(G)
inherit builtin_command;
#else
int main(int argc, array(string) argv) {
	mixed ex = catch {write("Result: %O\n", evaluate(argv[1..] * " "));};
	if (ex) write("Invalid expression: %s\n", (describe_error(ex) / "\n")[0]);
}
#endif
constant featurename = "info";
constant docstring = #"
Calculate something, possibly involving channel variables

Usage: `!calc 1 + 2 * 3`

If you are a moderator, this will expand variables. This is therefore
the quickest way to see the value of any variable:

`!calc $deaths$`

To avoid leaking private variables to non-moderators, unfortunately
this feature must be restricted. But numbers themselves are fine :)
";

//Define functions here that can be called in expressions

int|float func_random(array(int|float) args) {
	if (sizeof(args) != 1) error("random() requires precisely one argument\n");
	//If it looks like an integer, return a random integer.
	if (args[0] == (int)args[0]) return random((int)args[0]);
	return random(args[0]); //Otherwise a float.
}

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

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

int|float evaluate(string formula) {
	parser->set_error_handler(throw_errors);
	string next() {
		if (formula == "") return "";
		sscanf(formula, "%*[ \t\n]%s", formula); //TODO: Handle whitespace in the grammar properly
		sscanf(formula, "%[*&|<=>!]%s", string token, formula); //All characters that can be part of multi-character tokens
		if (token == "") sscanf(formula, "%1s%s", token, formula); //Otherwise, grab a single character
		return token;
	}
	return parser->parse(next, this);
}

constant command_description = "Calculate a simple numeric expression/formula";
constant builtin_description = "Perform arithmetic calculations";
constant builtin_name = "Calculator";
constant builtin_param = "Expression";
constant default_response = ([
	"conditional": "string", "expr1": "{error}", "expr2": "",
	"message": "@$$: {result}",
	"otherwise": "@$$: {error}",
]);
constant vars_provided = ([
	"{error}": "Blank if all is well, otherwise an error message",
	"{result}": "The result of the calculation",
]);
mapping message_params(object channel, mapping person, string param) {
	if (param == "") return (["{error}": "Usage: !calc 1+2", "{result}": ""]);
	if (person->badges->?_mod) param = channel->expand_variables(param);
	mixed ex = catch {
		int|float result = evaluate(param);
		//"!calc 1.5 + 2.5" will give a result of 4.0, but it's nicer to say "4"
		if (floatp(result) && result == (float)(int)result) result = (int)result;
		return (["{error}": "", "{result}": sprintf("%O", result)]);
	};
	return (["{error}": "Invalid expression [" + (describe_error(ex)/"\n")[0] + "]", "{result}": ""]);
}

#if constant(G)
protected void create(string name) {::create(name); G->G->evaluate_expr = evaluate;}
#endif
