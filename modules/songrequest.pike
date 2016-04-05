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
MAY be sufficient.)

The player is pretty simple. Invoke "cvlc --play-and-exit filename.m4a"
and have an event on its termination. Edge cases: There might not be any
currently-downloaded files (eg on first song request), so the downloader
may need to trigger the player. Also, it's entirely possible for playback
to stall; might need a mod-only command to kill it and start the next
track (maybe that can just be called !nextsong or something).
*/

string process(object channel, object person, string param)
{
	return "@$$: Song requests are not yet implemented.";
}
