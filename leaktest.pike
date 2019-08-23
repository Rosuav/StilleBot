mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);
mapping headers = (["Authorization": replace(irc["pass"], "oauth:", "OAuth "), "Client-ID": irc["clientid"]]);
string channel = "rosuav";

//Code lifted from Pike's Protocols.HTTP.Promise (GPLv2) for testing
protected class Session
{
  inherit Protocols.HTTP.Session : parent;
  class Request
  {
    inherit parent::Request;
    protected void async_fail(object q)
    {
      con->set_callbacks(0, 0);
      array eca = extra_callback_arguments;
      function fc = fail_callback;
      set_callbacks(0, 0, 0); // drop all references
      fc(Protocols.HTTP.Promise.Result(url_requested, q, eca && eca[1..]));
    }

    protected void async_ok(object q)
    {
      con->set_callbacks(0, 0);
      con->timed_async_fetch(async_data, async_fail); // start data downloading
    }

    protected void async_data() {
      string s = con->data();
      con->set_callbacks(0, 0);

      array eca = extra_callback_arguments;
      function dc = data_callback;
      set_callbacks(0, 0, 0); // drop all references

      if (dc) {
        Protocols.HTTP.Promise.Result ret = Protocols.HTTP.Promise.Result(url_requested, con, eca && eca[1..], s);
        dc(ret);
      }
    }

    //If this function is removed, Session::_destruct isn't called either.
    //If it's present, even with no code in it, Session::_destruct IS called.
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
                                   Protocols.HTTP.Promise.Arguments args)
{
  Concurrent.Promise p = Concurrent.Promise();
  Session s = Session(); //If this is retained, the leak vanishes

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
