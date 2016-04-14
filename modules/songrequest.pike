inherit command;
constant require_allcmds = 1;
inherit menu_item;
constant menu_label = "Song requests";
/* Song requests with a download cache and VLC.

The queue needs to acknowledge that a file may not yet have been fully
downloaded. TODO: How do we detect broken files? Can we have youtube-dl
not give them the final file names until it's confident? (It already has
the concept of .part files for ones that aren't fully downloaded. This
MAY be sufficient.) TODO: Allow mods to say "!songrequest force youtubeid"
to delete and force redownloading.

The player is pretty simple. Invoke "cvlc --play-and-exit filename.m4a"
and have an event on its termination. Edge cases: There might not be any
currently-downloaded files (eg on first song request), so the downloader
may need to trigger the player.

TODO: Flexible system for permitting/denying song requests. For example,
permit mods only, or followers/subs only (once StilleBot learns about
who's followed/subbed); channel currency cost, which could be different
for different people ("subscribers can request songs for free"); and
maybe even outright bannings ("FredTheTroll did nothing but rickroll us,
so he's not allowed to request songs any more").
*/

void statusfile()
{
	array nowplaying = G->G->songrequest_nowplaying;
	string msg;
	if (nowplaying)
	{
		msg = sprintf("[%s] %s", describe_time_short(nowplaying[0]), nowplaying[1]);
		//Locate the metadata block by scanning backwards.
		//There'll be meta entries for all requests, moving forward. There may be
		//any number of meta entries *behind* the current request, so always count back.
		mapping meta = persist["songrequest_meta"][-1-sizeof(persist["songrequests"])];
		msg += sprintf("\nRequested by %s at %s", meta->by, ctime(meta->at)[..<1]);
	}
	else
	{
		//Not playing any requested song. Maybe we have a playlist song.
		//We don't track lengths of those, though.
		if (G->G->songrequest_player) msg = explode_path(G->G->songrequest_lastplayed)[-1];
		else msg = "(nothing)";
	}
	Stdio.write_file("song_cache/nowplaying.txt", msg + "\n");
	G->G->songrequest_nowplaying_info = msg;
}

array(function) status_update = ({statusfile}); //Call this to update all open status windows (and the status file)

mapping(string:array) read_cache()
{
	mapping(string:array) cache = ([]);
	foreach (get_dir("song_cache"), string fn)
	{
		if ((<"README", "nowplaying.txt">)[fn]) continue;
		sscanf(fn, "%d-%11[^\n]-%s", int len, string id, string title);
		if (has_suffix(title, ".part")) continue; //Ignore partial files
		cache[id] = ({len, title, fn, id});
	}
	return cache;
}

void check_queue()
{
	if (check_queue != G->G->check_queue) {G->G->check_queue(); return;}
	object p = G->G->songrequest_player;
	if (p && !p->status()) return; //Already playing something.
	m_delete(G->G, "songrequest_nowplaying");
	call_out(status_update, 0);
	if (string chan = G->G->songrequest_channel)
	{
		//Disable song requests once the channel's offline or has song reqs disabled
		if (!persist["channels"][chan]->songreq) return; //Song requests are not currently active.
		if (!G->G->stream_online_since[chan]) return; //Song requests are available only while the channel is online.
	}
	mapping(string:array) cache = read_cache();
	string fn = 0;
	foreach (persist["songrequests"], string song)
	{
		if (G->G->songrequest_downloading[song]) continue; //Can't play if still downloading (or can we??)
		persist["songrequests"] -= ({song});
		if (!cache[song]) continue; //Not in cache and not downloading. Presumably the download failed - drop it.
		//Okay, so we can play this one.
		G->G->songrequest_nowplaying = cache[song];
		fn = "song_cache/"+cache[song][2];
		break;
	}
	if (!fn && sizeof(G->G->songrequest_playlist))
		//Nothing in song request queue, but we have a playlist.
		[fn, G->G->songrequest_playlist] = Array.shift(G->G->songrequest_playlist);
	if (fn)
	{
		G->G->songrequest_lastplayed = fn;
		G->G->songrequest_started = time();
		//We have something to play!
		G->G->songrequest_player = Process.create_process(
			({"cvlc", "--play-and-exit", fn}),
			([
				"callback": check_queue,
				"stdout": Stdio.File("/dev/null", "w")->pipe(Stdio.PROP_IPC),
				"stderr": Stdio.File("/dev/null", "w")->pipe(Stdio.PROP_IPC),
			])
		);
	}
}

class menu_clicked
{
	inherit window;
	constant is_subwindow = 0;
	void create() {::create(); status_update += ({update});}
	void closewindow() {status_update -= ({update}); ::closewindow();}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Song request status"]))->add(GTK2.Vbox(0, 10)
			->add(GTK2.Frame("Requested songs")->add(win->songreq=GTK2.Label()))
			->add(GTK2.Frame("Playlist")->add(win->playlist=GTK2.Label()))
			->add(GTK2.Frame("Downloading")->add(win->downloading=GTK2.Label()))
			->add(GTK2.Frame("Now playing")->add(win->nowplaying=GTK2.Label()))
			->add(GTK2.HbuttonBox()
				->add(win->add_playlist=GTK2.Button("Add to playlist"))
				->add(win->check_queue=GTK2.Button("Check queue"))
				->add(stock_close())
			)
		);
		update();
	}

	void update()
	{
		string reqs = "";
		mapping(string:array) cache = read_cache();
		foreach (persist["songrequests"], string song)
		{
			string downloading = G->G->songrequest_downloading[song] && " (downloading)";
			if (array c = cache[song])
				reqs += sprintf("[%s] %s%s\n", describe_time(c[0]), c[1], downloading || "");
			else
				if (downloading) reqs += song+" (downloading)\n";
		}
		win->songreq->set_text(reqs);
		win->playlist->set_text(G->G->songrequest_playlist*"\n");
		win->downloading->set_text(indices(G->G->songrequest_downloading)*"\n");
		string msg = G->G->songrequest_nowplaying_info;
		if (G->G->songrequest_player) msg += "\nBeen playing "+describe_time_short(time() - G->G->songrequest_started);
		win->nowplaying->set_text(msg);
	}

	void sig_add_playlist_clicked()
	{
		object dlg=GTK2.FileChooserDialog("Add file(s) to playlist",win->mainwindow,
			GTK2.FILE_CHOOSER_ACTION_OPEN,({(["text":"Send","id":GTK2.RESPONSE_OK]),(["text":"Cancel","id":GTK2.RESPONSE_CANCEL])})
		)->set_select_multiple(1)->show_all();
		dlg->signal_connect("response",add_playlist_response);
		dlg->set_current_folder(".");
	}

	void add_playlist_response(object dlg,int btn)
	{
		array fn=dlg->get_filenames();
		dlg->destroy();
		if (btn != GTK2.RESPONSE_OK) return;
		G->G->songrequest_playlist += fn;
		update();
	}

	void sig_check_queue_clicked()
	{
		check_queue();
		status_update();
		update();
	}
}

class youtube_dl(string videoid, string requser)
{
	inherit Process.create_process;
	Stdio.File stdout, stderr;
	string reqchan;

	void create(object channel)
	{
		reqchan = channel->name;
		stdout = Stdio.File(); stderr = Stdio.File();
		stdout->set_read_callback(data_received);
		::create(
			({"youtube-dl",
				"--prefer-ffmpeg", "-f","bestaudio",
				"-o", "%(duration)s-%(id)s-%(title)s",
				"--match-filter", "duration < " + channel->config->songreq_length,
				videoid
			}),
			([
				"callback": download_complete,
				"cwd": "song_cache",
				"stdout": stdout->pipe(Stdio.PROP_IPC|Stdio.PROP_NONBLOCK),
			])
		);
	}

	void data_received(mixed id, string data)
	{
		if (sscanf(data, "[download] %s does not pass filter duration < %d, skipping", string title, int maxlen))
		{
			//TODO: Run "youtube-dl --prefer-ffmpeg --get-duration "+videoid, and show the actual duration
			//NOTE: This does *not* remove the entries from the visible queue, as that would mess with
			//the metadata array. They will be quietly skipped over once they get reached.
			send_message(reqchan, sprintf("@%s: Video too long [max = %s]: %s", requser, describe_time(maxlen), title));
			return;
		}
	}

	void download_complete()
	{
		wait();
		stdout->close();
		stderr->close();
		m_delete(G->G->songrequest_downloading, videoid);
		check_queue();
	}
}

string process(object channel, object person, string param)
{
	if (!channel->config->songreq) return "@$$: Song requests are not currently active.";
	if (!G->G->stream_online_since[channel->name[1..]]) return "@$$: Song requests are available only while the channel is online.";
	G->G->songrequest_channel = channel->name[1..];
	if (param == "status" && person->user == channel->name[1..])
	{
		foreach (sort(get_dir("song_cache")), string fn)
		{
			if (fn == "README") continue;
			sscanf(fn, "%d-%s-%s", int len, string id, string title);
			int partial = has_suffix(title, ".part"); if (partial) title = title[..<5];
			send_message(channel->name, sprintf("%s: [%s]: %s %O",
				partial ? "Partial download" : "Cached file",
				describe_time(len), id, title));
		}
		foreach (G->G->songrequest_downloading; string videoid; object proc)
			send_message(channel->name, "Currently downloading "+videoid+": status "+proc->status());
		if (array x=G->G->songrequest_nowplaying)
			send_message(channel->name, sprintf("Now playing [%s]: %O", describe_time(x[0]), x[1]));
		return "Song queue: "+persist["songrequests"]*", ";
	}
	if (param == "skip" && channel->mods[person->user])
	{
		object p = G->G->songrequest_player;
		if (!p) return "@$$: Nothing currently playing.";
		p->kill(signum("SIGINT"));
		return "@$$: Song skipped.";
	}
	if (param == "flush" && channel->mods[person->user])
	{
		persist["songrequests"] = ({ });
		return "@$$: Song request queue flushed. After current song, back to the playlist.";
	}
	//Attempt to parse out a few common link formats
	//TODO: Support sources other than Youtube itself - youtube-dl can.
	//This will require less stringent parsing here, plus a different way of tagging the cache
	sscanf(param, "https://youtu.be/%s", param);
	sscanf(param, "https://www.youtube.com/watch?v=%s", param);
	sscanf(param, "?v=%s", param);
	sscanf(param, "v=%s", param);
	sscanf(param, "%s&", param); //If any of the previous ones has "?v=blah&other-info=junk", trim that off
	if (sizeof(param) != 11) return "@$$: Try !songrequest YOUTUBE-ID";
	if (G->G->songrequest_nowplaying && G->G->songrequest_nowplaying[3] == param)
		return "@$$: That's what's currently playing!";
	if (has_value(persist["songrequests"], param)) return "@$$: Song is already in the queue";
	mapping cache = read_cache();
	string msg;
	if (array info = cache[param])
	{
		if (info[0] > channel->config->songreq_length) return "@$$: Song too long to request [cache hit]";
		msg = "@$$: Added to queue [cache hit]";
	}
	else
	{
		if (G->G->songrequest_downloading[param]) msg = "@$$: Added to queue [already downloading]";
		else
		{
			G->G->songrequest_downloading[param] = youtube_dl(param, person->user, channel);
			msg = "@$$: Added to queue [download started]";
		}
	}
	//This is the only place where the queue gets added to.
	//This is, therefore, the place to add a channel currency cost, a restriction
	//on follower/subscriber status, or anything else the channel owner wishes.
	persist["songrequests"] += ({param});
	persist["songrequest_meta"] += ({(["by": person->user, "at": time()])});
	msg += sprintf(" - song #%d in the queue", sizeof(persist["songrequests"]));
	check_queue();
	return msg;
}

void create(string name)
{
	::create(name);
	//NOTE: Do not create a *file* called song_cache, as it'll mess with this :)
	if (!file_stat("song_cache"))
	{
		mkdir("song_cache");
		Stdio.write_file("song_cache/README", #"Requested song cache

Files in this directory have been downloaded by and in response to the !songrequest
command. See modules/songrequest.pike for more information. Any time StilleBot is
not running song requests, the contents of this directory can be freely deleted.
");
	}
	if (!G->G->songrequest_downloading) G->G->songrequest_downloading = ([]);
	if (!G->G->songrequest_playlist) G->G->songrequest_playlist = ({ });
	if (!persist["songrequests"]) persist["songrequests"] = ({ });
	if (!persist["songrequest_meta"]) persist["songrequest_meta"] = ({ });
	G->G->check_queue = check_queue;
}
