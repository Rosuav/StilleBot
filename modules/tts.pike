inherit command;
constant hidden_command = 1;
constant require_moderator = 1;
constant active_channels = ({"rosuav"});

/*
Chat vocalization for the VOD. This is stupid. This is useless. This is nothing more than
a silly toy by an insane programmer. So let's do it.
  - espeak "Hello world" --stdout|paplay /proc/self/fd/0 -d alsa_output.pci-0000_00_1f.3.iec958-stereo --volume 32768
  - Have a chat command to choose the output rather than hard coding it
  - Have a chat command to configure volume (65536 == max volume)
  - Every incoming message, add to a queue, with a minimum delay of (say) 2 seconds (configurable)
  - When the message comes up, check if it's been deleted (either individually or b/c the
    person has been banned/timed out), and if so, skip.
  - If the message is too old and there are too many in the queue, skip (so we catch up).
  - Ignore all emotes and possibly emoji
  - Attempt to read the user names?
  - Alternatively, can I do the whole thing in a web browser? Call on the same thing that does
    TTS for StreamLabs and Google (I think it's a Google service).
  - Is it possible to adjust speech speed? It is with espeak (-s 175 is default, try 250-300).
  - Can the actual text and emotes be encoded in some unobtrusive way???
    - Would basically require a form of audio steganography that is compression-safe. I'm using
      48KHz stereo audio, so in theory, very very short 'pips' in the 20KHz range could be used
      to carry signal. I'm not sure how well that would work though.
*/

//Thread to do the talking
void talker()
{
	Thread.Queue queue = G->G->tts_queue;
	while (1)
	{
		mapping msg = queue->read();
		if (msg->type == "end") break;
		int delay = msg->after - time();
		if (delay > 0) sleep(delay);
		write("*** TTS demo\n%O\n", msg);
	}
	G->G->tts_channel = 0;
	destruct(queue);
}

echoable_message process(object channel, object person, string param)
{
	if (param == "on")
	{
		if (G->G->tts_queue) return "TTS is already active (or still shutting down).";
		G->G->tts_channel = channel->name;
		G->G->tts_queue = Thread.Queue();
		G->G->tts_thread = Thread.Thread(talker);
		return "Now active.";
	}
	if (param == "off")
	{
		//TODO: Deactivate when channel goes offline too
		if (!G->G->tts_queue) return "TTS is not active.";
		G->G->tts_queue->try_read_array(); //Dump current contents of queue
		G->G->tts_channel = 0;
		G->G->tts_queue->write((["type": "end"]));
		return "Deactivating.";
	}
	if (param == "status")
	{
		if (!G->G->tts_queue) return "TTS is not active.";
		string msg = "TTS is active.";
		msg += sprintf(" Queue: %O", G->G->tts_queue);
		if (G->G->tts_queue) msg += sprintf(" (%d waiting)", G->G->tts_queue->size());
		msg += sprintf(" Thread: %O", G->G->tts_thread);
		if (G->G->tts_thread) msg += sprintf(" (status %d)", G->G->tts_thread->status());
		return msg;
	}
}

int message(object channel, object person, string msg)
{
	if (channel->name != G->G->tts_channel || !G->G->tts_queue) return 0;
	//HACK: Show only messages from moderators
	//TODO: Hook all message deletions and channel timeouts/bans, and dequeue those
	if (!person->badges || !person->badges->_mod) return 0;
	if (has_prefix(msg, "!")) return 0; //Ignore bot commands
	//TODO: Remove all emotes from the message, so they don't get read out
	G->G->tts_queue->write((["type": "message", "person": person, "msg": msg, "after": time() + 3]));
	return 0;
}

protected void create(string name)
{
	register_hook("all-msgs", message);
	::create(name);
}
