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
		if (b) yield(a += b); //bug workaround, shouldn't need if(b)
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

(TODO: Make this more of a tutorial or explanation, not a dump of an example.)

Putting the above two features together offers a powerful combination: a continue
function which yields Concurrent.Future objects until it has a true result, which
it then returns. This allows a simple and generic event loop to handle many such
functions simultaneously, and each one behaves as if it runs in its own lightweight
thread.

Define some tasks such as:

```
continue Concurrent.Future|mapping fetch_info(string url) {
	object res = yield(Protocols.HTTP.Promise.get_url(url));
	if (res->status >= 400) error("HTTP error %d fetching %s\n", res->status, url);
	mixed data = Standards.JSON.decode_utf8(res->get());
	if (!mappingp(data)) error("Malformed response\n");
	return data;
}

Concurrent.Future delay(float|int tm) {
	Concurrent.Promise p = Concurrent.Promise();
	call_out(p->success, tm, 0);
	return p->future();
}

continue Concurrent.Future read_stuff(string base) {
	int start = 0;
	while (1) {
		mapping data = yield(fetch_info(url + "?start=" + start));
		//... process data
		if (!data->next) break;
		start = data->next;
	}
	exit(0);
}

continue Concurrent.Future show_progress() {
	while (1) {
		foreach ("/-\\|";; int c) {
			yield(delay(0.25));
			write("%c\r", c);
		}
	}
}
```

The crucial asynchronicity handler looks like this:

```
class spawn_task(mixed gen, function|void got_result, function|void got_error) {
	array extra;
	protected void create(mixed ... args) {
		extra = args;
		if (!got_result) got_result = lambda() { };
		if (!got_error) got_error = _unhandled_error;
		if (functionp(gen)) pump(0, 0);
		else if (objectp(gen) && gen->then)
			gen->then(got_result, got_error, @extra);
		else got_result(gen, @extra);
	}
	void pump(mixed last, mixed err) {
		mixed resp;
		if (mixed ex = catch {resp = gen(last){if (err) throw(err);};}) {got_error(ex, @extra); return;}
		if (undefinedp(resp)) got_result(last, @extra);
		else if (functionp(resp)) spawn_task(resp, pump, propagate_error);
		else if (objectp(resp) && resp->then) resp->then(pump, propagate_error);
		else pump(resp, 0);
	}
	void propagate_error(mixed err) {pump(0, err);}
}
```

And it's really easy to use!

```
int main() {
	spawn_task(show_progress());
	spawn_task(read_stuff("http://some.site.example/api/items"));
	return -1;
}
```

The same backend will run every task, meaning that the process is single-threaded
regardless of the number of tasks. Tasks may freely spawn additional tasks (for
instance, a socket listener task might spawn a task for each connected client),
and tasks may freely use all normal control flow, without the hassles of looping
across promises or callbacks.


Interfacing between asynchronicity styles
-----------------------------------------

Or: Rosetta Stone of asynchronous code.

### Concurrent.Future and callbacks ###

```
Concurrent.Future promisify(function func, mixed ... args) {
	//Shorthand if the function takes two callbacks, success and failure:
	//return Concurrent.Promise(func, @args)->future();
	//Otherwise, doing it manually:
	Concurrent.Promise p = Concurrent.Promise();
	func(@args, p->success); //When p->success(x) is called, the promise will resolve with x.
	return p->future();
}

void call_me_maybe(Concurrent.Future fut, function cb) {
	fut->then(cb);
}
```

### Generator and Concurrent.Future ###

Generators with the spawn_task executor are built on top of futures, so these
two work well together.

```
continue Concurrent.Future wait_for(Concurrent.Future fut) {
	mixed ret = yield(fut);
	return ret;
}

Concurrent.Future generate_promise(function g) {
	Concurrent.Promise p = Concurrent.Promise();
	spawn_task(g, p->success, p->failure);
	return p->future();
}
```

### Generator and callbacks ###

spawn_task can call a callback when the task completes, so it is inherently able
to translate in that direction. If you have a function which expects a callback,
the easiest way to use it in a continue function is to first promisify it.

```
continue Concurrent.Future wait_for(function func) {
	mixed ret = yield(promisify(func));
	return ret;
}
```
