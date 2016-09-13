//Recursively enumerate files in a directory
array(string) all_files(string dir)
{
	array ret = ({ });
	foreach (sort(get_dir(dir)), string fn)
	{
		fn = dir+"/"+fn;
		if (file_stat(fn)->isdir) ret += all_files(fn);
		else ret += ({fn});
	}
	return ret;
}

//Policy: Everything possible here should also be possible through the GUI.
//This won't always be perfect (eg multi-select in a file dlg is not the same
//as recursively collecting files from a dir, for "/playlist"), but since the
//commands here are completely non-discoverable, it's much better to not work
//in a way that some users will be completely unable to use.
//But having /update here is a Good Thing, in situations of GUI breakage :)
//Note that the console is entirely unavailable on Windows; but development
//on Windows sucks anyway, so the assumption is that this will be deployed.
void execcommand(string line)
{
	if (sscanf(line, "/join %s", string chan))
	{
		if (persist["channels"][chan]) {write("%%% Already joined.\n"); return;}
		write("%%% Joining #"+chan+"\n");
		G->G->irc->join_channel("#"+chan);
		persist["channels"][chan] = ([]);
		persist->save();
	}
	else if (sscanf(line, "/part %s", string chan))
	{
		write("%%% Parting #"+chan+"\n");
		G->G->irc->part_channel("#"+chan);
		if (m_delete(persist["channels"], chan)) persist->save();
	}
	else if (line == "/update")
	{
		werror("%%% Reloading all...\n");
		G->bootstrap_all();
		werror("%%% Reload completed.\n");
	}
	else if (sscanf(line, "/update %s", string file))
	{
		werror("%%% Updating "+file+"\n");
		G->bootstrap(file);
	}
	else if (sscanf(line, "/playlist %s", string dir))
	{
		if (dir == "clear")
		{
			G->G->songrequest_playlist = ({ });
			werror("%%% Cleared playlist.\n");
			return;
		}
		werror("%%% Adding playlist files from "+dir+"...\n");
		G->G->songrequest_playlist += all_files(dir);
		werror("%%% Playlist now has "+sizeof(G->G->songrequest_playlist)+" files.\n");
	}
}

void create()
{
	G->execcommand = execcommand;
}
