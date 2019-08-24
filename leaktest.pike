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
	write("kept %O inuse %O cache %O\n", connections_kept_n, connections_inuse_n, connection_cache);
	int fds = sizeof(get_dir("/proc/self/fd"));
	//~ destruct(query->con); //Does not solve the problem
	//~ query->con->close(); query->con = 0; //DOES solve the problem
	::return_connection(url, query);
	write("kept %O inuse %O cache %O\n", connections_kept_n, connections_inuse_n, connection_cache);
	write("Returned %d fds\n", fds - sizeof(get_dir("/proc/self/fd")));
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
*/
Session gsess;
void poll()
{
	call_out(poll, 3);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	Session lsess = gsess || Session();
	//lsess->async_do_method_url("GET", "https://sikorsky.rosuav.com/", 0, 0, 0, 0, //Connection: close
	lsess->async_do_method_url("GET", "https://pike.lysator.liu.se/", 0, 0, 0, 0, //Connection: keep-alive
		lambda(string res) {
			write("%O\n", res[..27]);
			//write("%O %O %O\n", lsess->connections_kept_n, lsess->connections_inuse_n, lsess->connection_cache);
		}, 0, ({ }));
}

void readable(object sock, string data) {write("%O\n", (data/"\r\n\r\n")[1]);}
void writable(object sock) {sock->write("GET / HTTP/1.0\r\n\r\n"); sock->set_nonblocking(readable, 0, 0);}
void connected(object sock)
{
	write("Connected\n");
	object ssl = SSL.File(sock, SSL.Context());
	ssl->connect("sikorsky.rosuav.com");
	ssl->set_nonblocking(readable, writable, 0);
}
int sslonly()
{
	//Just create and destruct() a bunch of SSL.File objects
	call_out(sslonly, 3);
	write("Spinning... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	object sock = Stdio.File(); sock->open_socket();
	sock->set_nonblocking(readable, connected, 0);
	sock->connect("sikorsky.rosuav.com", 443);
	return -1;
}

int main(int argc, array(string) argv)
{
	if (has_value(argv, "--sslonly")) return sslonly();
	if (has_value(argv, "--retain")) gsess = Session();
	write("My PID is: %d\n", getpid());
	poll();
	return -1;
}
