# $$title||Followed streams$$

> ### Preferences
> Choose which tags you like or dislike. Liked tags will be promoted among<br>
> followed streams; disliked tags will be correspondingly demoted. Preferences<br>
> will affect Magic sort, beginning the next time you load the page.
>
> <ul></ul>
>
> Viewer counts: <label><input type=radio name=viewership data-tagid="<viewership>" class=liketag> Visible</label> <label><input type=radio name=viewership data-tagid="<viewership>" class=disliketag> Invisible</label>
>
> Allow suggestions? <label><input type=radio name=raidsuggestions data-tagid="<raidsuggestions>" class=liketag> Yes, from anyone</label> <label><input type=radio name=raidsuggestions data-tagid="<raidsuggestions>" class=disliketag> No suggestions</label>
{: tag=dialog #tags}

<button id=legend>Legend/info</button> <button id=highlights>Edit highlight list</button>
<button id=allraids>All recent raids</button> <button id=tagprefs>Preferences</button>
<button id=mydetails>This stream's info</button>

* $$sortorders$$
{: #sort}

<div id=streams class="streamtiles sizeborders"></div>
<div id=copied>Copied!</div>

> <span id=notes_about_channel>Channel name: </span>
>
> <form method=dialog>
> <textarea rows=8 cols=50></textarea>
> <button value="save">Save</button> <button value="cancel">Cancel</button>
> </form>
{: tag=dialog #editnotes}

<a id=yourcat href="#" target="_blank">Current category: ??</a><br>
<a href="raidfinder?categories" target="_blank">Categories you follow</a><br>
<a href="raidfinder?allfollows" target="_blank">All channels you follow</a>

> ### Raids to or from this channel:
> <ul></ul>
{: tag=dialog #raids}

<style>
.streamtiles {
	display: flex;
	flex-wrap: wrap;
	justify-content: space-around;
}
.streamtiles > div {
	width: 324px; /* the width of the preview image plus border size */
	margin-bottom: 1em;
}
.streamtiles ul {list-style-type: none; margin: 0; padding: 0; flex-grow: 1;}
.streamtiles li:not(.no-indent) {
	padding-left: 2em;
	text-indent: -2em;
}
.avatar {max-width: 40px;}
.inforow {display: flex; overflow-x: clip;}
.inforow .img {flex-grow: 0; padding: 0.25em;}
.streamtitle {font-size: 85%;}
.emote {max-height: 1.25em;}
.tag {
	display: inline-block;
	padding: 0 0.125em; text-indent: 0; /* Override the general text-wrap settings from above */
	background: #ddd;
	margin-right: 0.5em;
	font-size: 80%;
}
.tag.autotag {
	font-style: italic;
}
.tagpref-3 {background-color: #d99; border: 1px solid red;}
.tagpref-2 {background-color: #ecc; border: 1px solid red;}
.tagpref-1 {background-color: #fee; border: 1px solid red;}
.tagpref0 {border: 1px solid transparent;}
.tagpref1 {background-color: #dfd; border: 1px solid green;}
.tagpref2 {background-color: #beb; border: 1px solid green;}
.tagpref3 {background-color: #9d9; border: 1px solid green;}

.tag {border: 1px solid black;} /* Ensure that .tagpref1.tag has a black border not the green one */

#sort::before {content: "Sort: "; margin: 0.5em 1em 0em -1em;}
#sort {
	display: flex;
	list-style-type: none;
}
#sort li {
	cursor: pointer;
	margin: 0.25em;
	padding: 0.25em;
	text-decoration: solid underline;
}
#sort li.current {text-decoration: double underline;}
.uptime {cursor: pointer;}
.raid-incoming {font-weight: bold;}
.raid-incoming,.raid-outgoing {cursor: pointer;}
.notes {margin-right: 0.5em;}
.notes.absent {filter: grayscale(1);}
main {max-width: none!important;} /* Override the normal StilleBot style */

.bcasttype {
	background-color: purple;
	color: white;
	border-radius: 50%;
}

.highlighted {
	background-color: #ffc;
	border: 1px solid #ff0;
}

.sizeborders > div {border: 2px solid transparent;}
.sizeborders > div.much_smaller     {border-color: #bfe;}
.sizeborders > div.smaller          {border-color: #cfe;}
.sizeborders > div.slightly_smaller {border-color: #dfe;}
.sizeborders > div.samesize         {border-color: #efe;}
.sizeborders > div.slightly_larger  {border-color: #efd;}
.sizeborders > div.larger           {border-color: #efc;}
.sizeborders > div.much_larger      {border-color: #efb;}

#viewerlegend {display: flex;}
#viewerlegend div {margin-right: 0.5em; padding: 0.25em 0.125em;}

#vodlengths {width: min-content;}
#vodlengths li {
	width: 500px; /* TODO: Shrink this on narrow screens (but how much?) */
	margin-right: 25px;
}
.is_following {background: #eef;}
.not_following {background: #ddf; border: 1px solid blue;}

.magic-score {
	display: inline-block;
	min-width: 2em;
	text-align: end;
}

#chat_restrictions li {
	background: red;
	color: yellow;
	font-weight: bold;
	padding: 2px 6px;
	margin: 2px 0;
	list-style-type: none;
	width: max-content;
}

.uptime .warning {
	background: yellow;
	margin-right: 0.25em;
}
.uptime .info {
	background: #aaf;
	margin-right: 0.25em;
}
.uptime .allclear {
	background: #a0f0c0;
	margin-right: 0.25em;
}
.uptime .new_frond {
	margin-right: 0.25em;
}

#raid_command {
	background: #eef;
	border: 1px solid blue;
	margin: 0 3px;
	padding: 5px;
}

.streamtiles .annotation {
	font-size: 75%;
	max-width: max-content;
	margin: auto;
	border: 1px solid rebeccapurple;
	background: #e3e3e3;
}

#raidsuggestions {
	position: fixed;
	top: 40px; right: 40px;
	background: rebeccapurple;
	color: white;
	border: 1px solid #a0f0c0;
	cursor: pointer;
}
</style>

> ### Legend/info
> This raid finder shows the people you currently follow, and helps you select someone<br>
> to raid. Incoming and outgoing raids $$is_tracked||will be shown if StilleBot tracks this channel$$.
>
> The recommendations sort order is based upon the following factors:
>
> * Incoming raids, especially those more than a month ago
> * Few or no outgoing raids
> * Stream has fewer viewers than you or only slightly more
> * Stream has recently started
> * Both of you are in the same category, or related categories (currently only Creative)
> * Tags that both of you are using
>
> Followed channels have a subtle border highlight to show viewer count relative to your own.
> <div id=viewerlegend class=sizeborders>
> <div class=much_larger>Double</div>
> <div class=larger>50% more</div>
> <div class=slightly_larger>25% more</div>
> <div class=samesize>About the same</div>
> <div class=slightly_smaller>20% fewer</div>
> <div class=smaller>33% fewer</div>
> <div class=much_smaller>Half</div>
> </div>
{: tag=dialog #infodlg}

<!-- break dialogs apart -->

> ### Previous stream lengths
>
> Green bars represent previous stream lengths, with current uptime shown as a red hairline.
> Streams precisely a week ago, two weeks ago, etc, are vibrant green, with paler green for
> streams at other times of the week.
>
> Dates and times are in your local time zone.
>
> <span id=is_following></span>
> <ul id=chat_restrictions></ul>
>
> <ul id=vods></ul>
{: tag=dialog #vodlengths}

<!-- break dialogs apart -->

> ### Go raiding!
>
> To raid this streamer, type <code id=raid_command></code> [📋](:.clipbtn) into your chat/dashboard!
>
> <p id=raidsuccess hidden>Raid successful! Your viewers should now be arriving at your raid target.<br>Don't forget to <b>stop the broadcast</b>!</p>
>
> $$raidbtn||$$ [Close](:.dialog_close)
{: tag=dialog #goraiding}

<ul id=raidsuggestions hidden></ul>

> ### Raid suggestions
>
> These suggestions have been submitted by your community.
>
> <div id=suggestedtiles class=streamtiles></div>
>
> [Close](:.dialog_close)
{: tag=dialog #raidsuggestionsdlg}
