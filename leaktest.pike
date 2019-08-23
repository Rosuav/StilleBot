mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);
mapping headers = (["Authorization": replace(irc["pass"], "oauth:", "OAuth "), "Client-ID": irc["clientid"]]);
string channel = "rosuav";

//Code lifted from Pike's Protocols.HTTP.Promise (GPLv2) for testing
protected class Session
{
  inherit Protocols.HTTP.Session : parent;

  public int(0..) maxtime, timeout;

  class Request
  {
    inherit parent::Request;

    protected void async_fail(object q)
    {
      // clear callbacks for possible garbation of this Request object
      con->set_callbacks(0, 0);

      array eca = extra_callback_arguments;
      function fc = fail_callback;
      set_callbacks(0, 0, 0); // drop all references

      if (fc) {
        Protocols.HTTP.Promise.Result ret = Protocols.HTTP.Promise.Result(url_requested, q, eca && eca[1..]);
        fc(ret);
      }
    }

    protected void async_ok(object q)
    {
      ::check_for_cookies();

      if (con->status >= 300 && con->status < 400 &&
          con->headers->location && follow_redirects)
      {
        Standards.URI loc = Standards.URI(con->headers->location,url_requested);

        if (loc->scheme == "http" || loc->scheme == "https") {
          destroy(); // clear
          follow_redirects--;
          do_async(prepare_method("GET", loc));
          return;
        }
      }

      // clear callbacks for possible garbation of this Request object
      con->set_callbacks(0, 0);

      if (data_callback)
        con->timed_async_fetch(async_data, async_fail); // start data downloading
      else
        extra_callback_arguments = 0; // to allow garb
    }

    protected void async_data() {
      string s = con->data();

      if (!s)		// data incomplete, try again later
        return;

      // clear callbacks for possible garbation of this Request object
      con->set_callbacks(0, 0);

      array eca = extra_callback_arguments;
      function dc = data_callback;
      set_callbacks(0, 0, 0); // drop all references

      if (dc) {
        Protocols.HTTP.Promise.Result ret = Protocols.HTTP.Promise.Result(url_requested, con, eca && eca[1..], s);
        dc(ret);
      }
    }

    protected void _destruct() {				
      werror("%O()._destruct()\n", object_program(this)); 
    }
  }


  class SessionQuery
  {
    inherit parent::SessionQuery;

    protected void create()
    {
      if (Session::maxtime) {
        this::maxtime = Session::maxtime;
      }

      if (Session::timeout) {
        this::timeout = Session::timeout;
      }
    }

    protected void _destruct() {			
      werror("%O()._destruct()\n", object_program(this));
    }
  }

  protected void _destruct() {				
    werror("%O()._destruct()\n", object_program(this)); 
  }
}

public Concurrent.Future do_method(string http_method,
                                   Protocols.HTTP.Session.URL url,
                                   void|Protocols.HTTP.Promise.Arguments args)
{
  if (!args) {
    args = Protocols.HTTP.Promise.Arguments();
  }

  Concurrent.Promise p = Concurrent.Promise();
  Session s = Session();

  s->async_do_method_url(http_method, url,
                         args->variables,
                         args->data,
                         args->headers,
                         0, // headers received callback
                         lambda (Protocols.HTTP.Promise.Result ok) {
                           p->success(ok);
                         },
                         lambda (Protocols.HTTP.Promise.Result fail) {
                           p->failure(fail);
                         },
                         args->extra_args || ({}));
  return p->future();
}
//End GPLv2 code from Pike

void poll()
{
	call_out(poll, 3);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	do_method("GET", "https://api.twitch.tv/helix/streams?user_login=" + channel,
		Protocols.HTTP.Promise.Arguments((["headers": headers])))
		->on_success(lambda(Protocols.HTTP.Promise.Result res) {
			mixed raw = Standards.JSON.decode_utf8(res->get());
			if (!sizeof(raw->data)) write("** Channel %s is offline **\n", channel);
			else write("** Channel %s went online at %s **\n", channel, raw->data[0]->started_at);
		});
}

int main() {write("My PID is: %d\n", getpid()); poll(); return -1;}
