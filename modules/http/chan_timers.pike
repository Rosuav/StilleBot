inherit http_websocket;

/* Subset of functionality from mustard-mine.herokuapp.com:
* It can be autostarted on page activation - good for a break timer.
  - On WS connection, if timer not active, start with a known countdown
* Have a builtin to manipulate timers
* Timers can be set to a specific duration ("10 minute countdown") or a defined target (using your timezone).
  - Can be linked to your Twitch schedule (see get_stream_schedule()) to define the target.
  - Note that this will likely mean that schedule updates become crucial.
    - Obviously will require a call to get_stream_schedule inside get_chan_state
    - What if the schedule changes while the browser source is open? When will we notice?
      There's no EventSub message relating to the schedule, sadly.
    - Have centralized fetching of the schedule. Any time we fetch for the sake of the front end,
      it can send_updates_all() to make changes take effect.
* Provide three states, with formatting options:
  - Timer active. Goal is in the near future.
  - Timer completed. Goal is in the past.
  - Timer inactive. Goal is in the distant future.
  - The definition of "near" and "distant" should be configurable; default to one hour.
  - For timers tied to the Twitch schedule, recommend that "completed" and "inactive" be treated identically,
    as a recurring schedule will usually result in completed timers migrating to the next event, most likely
    putting them into "inactive" state.
  - Allow custom textformatting for Completed and Inactive, but have a "delete" button that leaves it unchanged
    (ie identical to Active) as this will be the most common.
  - Notably, this can be used to show different text, including different formatting of the countdown time.
  - Allow variables in this text?

*/

constant markdown = #"# Stream timers

TODO.
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(G->G->DB->load_config(channel->userid, "streamsetups"));
	return ([
		"checklist": info->checklist || "",
		"items": info->setups || ({ }),
	]);
}
