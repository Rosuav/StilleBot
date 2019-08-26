//Code lifted from Pike's Protocols.HTTP.Promise (GPLv2) for testing
protected class Session
{
  inherit Protocols.HTTP.Session : parent;
  class Request
  {
    inherit parent::Request;
    protected void async_ok(object q)
    {
      con->set_callbacks(0, 0);
      con->timed_async_fetch(async_data, async_fail); // start data downloading
    }

    protected void async_data() {
      string s = con->data();
      con->set_callbacks(0, 0);
      function dc = data_callback;
      set_callbacks(0, 0, 0); // drop all references
      dc(s);
    }
  }
  void return_connection(Standards.URI url,object query)
  {
	write("Returning connection %O\n", query);
	write("con: %O\n", query->con);
	write("kept %O inuse %O\n", connections_kept_n, connections_inuse_n);
	int fds = sizeof(get_dir("/proc/self/fd"));
	//~ destruct(query->con); //Does not solve the problem
	//~ query->con->close(); query->con = 0; //DOES solve the problem
	::return_connection(url, query);
	write("kept %O inuse %O\n", connections_kept_n, connections_inuse_n);
	write("Returned %d fds\n", fds - sizeof(get_dir("/proc/self/fd")));
  }
  protected void _destruct() {
    //if (con) destruct(con);
    werror("%O()._destruct() %d in cache\n", object_program(this), `+(@sizeof(values(connection_cache)[*])));
    foreach (connection_cache;; array c) c->disconnect();
  }
}
//End GPLv2 code from Pike

/*
The rules seem to be different depending on whether the connection is
made over TLS or not. All tests have been done with https:// URLs.

With "Connection: keep-alive" in the HTTP response:
If the Session object is retained, the number of open file descriptors
stabilizes after a while. If a new one is created each iteration, open
FDs get leaked each iteration.

With "Connection: close" in the HTTP response:
Regardless of Session object retention, file descriptors are leaked.

The call to return_connection() always seems to close three FDs if
Connection: close, but it needs to close four.

It seems the Session is not getting garbage collected. Even creating it
with maximum_connection_reuse = 0 doesn't solve it, because the request
isn't returned to pool once the Result is yielded.

There appear to be THREE separate problems here.
1) TCP sockets are leaked because nothing ever returns them to the pool.
   In Promise::Session::Request, after sending the data, dispose of
   self, thus returning the connection (or destroying it if no KA).
2) With keep-alive, even though the session will never be reused, the
   sockets are leaked because the Session cannot be disposed of.
   In Promise::do_method, set s->maximum_connection_reuse to zero.
3) When using -DHTTP_PROMISE_DESTRUCT_DEBUG to add _destruct methods
   to various types, the DNS socket is leaked. Using an IP address
   avoids this leak, or call ::_destruct().
*/
Session gsess;
void poll()
{
	call_out(poll, 3);
	write("Polling... %d garbage, %d open files\n", gc(), sizeof(get_dir("/proc/self/fd")));
	Session lsess = gsess || Session();
	//lsess->async_do_method_url("GET", "https://sikorsky.rosuav.com/", 0, 0, 0, 0, //Connection: close
	lsess->async_do_method_url("GET", "https://pike.lysator.liu.se/", 0, 0, 0, 0, //Connection: keep-alive
		lambda(string res) {
			write("%O\n", res[..27]);
			//write("%O %O %O\n", lsess->connections_kept_n, lsess->connections_inuse_n, lsess->connection_cache);
			//call_out(destruct, 1, lsess);
		}, 0, ({ }));
}

void promises()
{
	call_out(promises, 3);
	write("Promising... %d garbage, %d open files\n", gc(), sizeof(get_dir("/proc/self/fd")));
	Protocols.HTTP.Promise.get_url("https://sikorsky.rosuav.com/")
	//Protocols.HTTP.Promise.get_url("https://192.168.0.19/") //No UDP leak
	//Protocols.HTTP.Promise.get_url("https://pike.lysator.liu.se/")
		->on_success(lambda(Protocols.HTTP.Promise.Result res) {
			string raw = res->get();
			write("%O\n", raw[..27]);
		});
}

int main(int argc, array(string) argv)
{
	if (has_value(argv, "--retain")) gsess = Session();
	write("My PID is: %d\n", getpid());
	if (has_value(argv, "--promise")) promises();
	else poll();
	return -1;
}
