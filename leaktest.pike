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
		}, 0, ({ }));
}

int main(int argc, array(string) argv)
{
	if (has_value(argv, "--retain")) gsess = Session();
	write("My PID is: %d\n", getpid());
	poll();
	return -1;
}
