#if constant(G)
inherit command;
#endif
//TODO-DOCSTRING

//Evaluate a string containing nothing but numeric literals and
//a restricted set of operations.
constant precedence = ([
	//Highest precedence - most tightly binding
	//Note: Exponentiation is not currently supported.
	"UNARY-": 6,
	"*": 5, "/": 5, "%": 5,
	"+": 4, "-": 4,
	">": 3, ">=": 3, "==": 3, "!=": 3, "<=": 3, "<": 3,
	"&&": 2, "||": 2, "!": 2,
	"(": 1, ")": 1,
	//Lowest precedence - least tightly binding
]);
constant operator_aliases = ([
	"=": "==", "~": "!", "~=": "!=", "=>": ">=", "<>": "!=",
	"&": "&&", "|": "||", "^=": "!=", "^": "!",
]);
void _eval_ops(object operands, object operators, int prec) {
	//Process all operators on the stack with higher precedence
	while (sizeof(operators) && precedence[operators->top()] > prec) {
		string op = operators->pop();
		//~ #define BINARY(o) case #o: operands->push(operands->pop() o operands->pop()); break
		#define BINARY(o) case #o: {mixed a=operands->pop(), b=operands->pop(); write("%O %s %O => %O\n", a, #o, b, a o b); operands->push(a o b);} break
		switch (op) {
			BINARY(+); BINARY(-); BINARY(*); BINARY(/); BINARY(%);
			BINARY(<); BINARY(<=); BINARY(==); BINARY(!=); BINARY(>=); BINARY(>);
			BINARY(&&); BINARY(||);
			case "UNARY-": write("Negating %O\n", operands->top()); operands->push(-operands->pop()); break;
			case "(": throw("Mismatched '('");
			default: throw("Unimplemented operator: " + op);
		}
		#undef BINARY
	}
}
int|float evaluate(string formula) {
	//Basic algorithm:
	//1) Skip whitespace
	//2) Grab one token. This could be:
	//   - a sequence of digits containing one decimal point: float
	//   - a sequence of digits NOT containing a decimal point: int
	//   - if following a number, any operator
	//   - if not following a number, any unary operator (currently just "-")
	//3) For numeric tokens, add to the operand stack
	//4) Operators go on the operator stack, and have a precedence
	//5) Parentheses count as operators but can instantly remove if paired
	//Note that there are no function calls here so x() is not special.
	object operands = ADT.Stack(), operators = ADT.Stack();
	int hyphen_is_unary = 1; //Uber-simplistic handling of unary operators
	while (1) {
		formula = String.trim(formula); //Note that whitespace WILL terminate a token
		if (formula == "") break;
		if (sscanf(formula, "%[0-9.]%s", string digits, formula) && digits && digits != "") {
			if (has_value(digits, '.')) operands->push((float)digits);
			else operands->push((int)digits);
			hyphen_is_unary = 0;
			continue;
		}
		//Parens get special handling since they must be matched
		//Note that this is a bit too permissive, and will allow some things that shouldn't be.
		if (sscanf(formula, "(%s", formula)) {
			operators->push("(");
			hyphen_is_unary = 1;
			continue;
		}
		if (sscanf(formula, ")%s", formula)) {
			_eval_ops(operands, operators, precedence["("]);
			if (!sizeof(operators) || operators->pop() != "(") throw("Mismatched ')'");
			//Actually don't have to change anything else - the operand will stay
			//on the top of the stack.
			hyphen_is_unary = 1;
			continue;
		}
		if (sscanf(formula, "%[-+*/%<>=|^&!~]%s", string oper, formula) && oper && oper != "") {
			oper = operator_aliases[oper] || oper;
			int prec = precedence[oper];
			if (!prec) throw("Unknown operator: " + oper);
			if (hyphen_is_unary && oper == "-") oper = "UNARY-";
			_eval_ops(operands, operators, prec);
			operators->push(oper);
			hyphen_is_unary = 1;
			continue;
		}
		//If we get here, there's some sort of invalid character.
		throw("TODO: better error messages");
	}
	_eval_ops(operands, operators, -1);
	if (sizeof(operands) > 1) throw("Too many numbers");
	if (!sizeof(operands)) throw("Not enough numbers");
	return operands->pop();
}

constant legal = "0123456789+-/*() ."; //For now, permit a VERY few characters, for safety.

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Usage: !calc 1+2";
	if (sizeof((multiset)(array)param - (multiset)(array)legal))
		return "@$$: Illegal character in expression";
	if (mixed ex=catch {
		int|float ret = compile("int|float _() {return "+param+";}")()->_();
		if (intp(ret) || floatp(ret)) return sprintf("@$$: %O", ret);
	}) return "@$$: Invalid expression [" + (describe_error(ex)/"\n")[0] + "]";
	//This shouldn't normally happen - anything that returns a non-int/float will
	//normally trigger a compilation error - but we don't want to be silent.
	return "@$$: Invalid expression [must have real result]";
}

int main(int argc, array(string) argv) {
	string formula = argv[1..] * " ";
	write("Evaluating: %O\n", formula);
	int|float result; 
	if (mixed error = catch {result = evaluate(formula);}) {
		if (stringp(error)) write("Error: %s\n", error); //Evaluator error
		else werror(describe_backtrace(error)); //Pike error
	}
	else write("Result: %O\n", result);
}
