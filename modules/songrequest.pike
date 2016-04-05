inherit command;
constant require_allcmds = 1;
/* Currently a stub for notetaking.

Proposal: Implement song requests using a download cache and VLC.

This will require:
* Downloader, triggered by the !songrequest command (this one)
* Global queue of requested songs
* Player

The queue needs to acknowledge that a file may not yet have been fully
downloaded. TODO: How do we detect broken files? Can we have youtube-dl
not give them the final file names until it's confident? (It already has
the concept of .part files for ones that aren't fully downloaded. This
MAY be sufficient.) TODO: Allow mods to say "!songrequest force youtubeid"
to delete and force redownloading.

The player is pretty simple. Invoke "cvlc --play-and-exit filename.m4a"
and have an event on its termination. Edge cases: There might not be any
currently-downloaded files (eg on first song request), so the downloader
may need to trigger the player. Also, it's entirely possible for playback
to stall; might need a mod-only command to kill it and start the next
track (maybe that can just be called !nextsong or something).

TODO: Flexible system for permitting/denying song requests. For example,
permit mods only, or followers/subs only (once StilleBot learns about
who's followed/subbed); channel currency cost, which could be different
for different people ("subscribers can request songs for free"); and
maybe even outright bannings ("FredTheTroll did nothing but rickroll us,
so he's not allowed to request songs any more").
*/

string process(object channel, object person, string param)
{
	return "@$$: Song requests are not yet implemented.";
}

void create()
{
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
}
