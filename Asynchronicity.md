Asynchronicity, Concurrent.Future, and continue functions
=========================================================

Pike has excellent features for running asynchronous code, such as a server that
handles large numbers of clients, performs database requests, and so on. Useful
abstractions over the basics of callbacks include promises/futures and continue
functions, which work together to create elegant single-threaded code which looks
as clean and readable as threaded code.

(NOTE: All descriptions here are based on Pike 8.1.15 as of mid-2021. If someone
wants to adjust things to match a specific 8.0 or 8.2 release, feel free.)

Concurrent.Future and its friends
---------------------------------

A function must return a value immediately. But if the truly meaningful value is
not ready yet, the function can instead promise to produce that value in the
future, returning a Concurrent.Future which can be consumed later.

The easiest way to use promises is to construct one, return its future, and then
call either its success or failure method when the result is known:

```
Concurrent.Future divide(int x, int y) {
	Concurrent.Promise p = Concurrent.Promise();
	call_out(low_divide, 1.0, p, x, y);
	return p->future();
}

void low_divide(Concurrent.Promise p, int x, int y) {
	if (!y) p->failure(({"Cannot divide by zero\n", backtrace()}));
	else p->success(x / y);
}
```

This can be used as follows:

```
void perform_calculations() {
	divide(20, 5)->then(lambda(int result) {
		write("The result is: %d\n", result);
	});
}
```

This is a perfect place to make use of implicit lambda functions too:

```
void perform_calculations() {
	divide(20, 5)->then() {[int result] = __ARGS__;
		write("The result is: %d\n", result);
	};
}
```

Continue Functions
------------------

Rather than returning a single value and then finishing, a continue function can,
as the name suggests, yield a value and continue running. When you call such a
function, you get back a state function which keeps track of everything that the
continue function was doing, and can be resumed until the function is done.

```
continue int fibonacci() {
	int a = 0, b = 1;
	while (1) {
		yield(a += b);
		yield(b += a);
	}
}
```

This will produce an infinite stream of Fibonacci numbers. It can be used thus:

```
int main() {
	function fib = fibonacci();
	while (1) {
		write("--> %d\n", fib());
		sleep(0.125);
	}
}
```

A continue function can return, either with the regular `return` statement or by
running off the end, just as other functions do. The value thus produced will be
the last value returned by the state function, and then the state function will
return 0 thereafter.

Asynchronous functions with yield points
----------------------------------------

Putting the above two features together offers a powerful combination: a continue
function which yields Concurrent.Future objects until it has a true result, which
it then returns. This allows a simple and generic event loop to handle many such
functions simultaneously, and each one behaves as if it runs in its own lightweight
thread.

