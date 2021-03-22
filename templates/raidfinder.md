# $$title||Followed streams$$

> ### Tag preferences
> Choose which tags you like or dislike. Liked tags will be promoted among
> followed streams; disliked tags will be correspondingly demoted. Preferences
> will affect Magic sort, beginning the next time you load the page.
>
> <ul></ul>
{: tag=dialog #tags}

<button id=legend>Legend/info</button> <button id=highlights>Edit highlight list</button>
<button id=allraids>All recent raids</button> <button id=tagprefs>Tag preferences</button>

* $$sortorders$$
{: #sort}

<div id=streams></div>

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
#streams {
	display: flex;
	flex-wrap: wrap;
	justify-content: space-around;
}
#streams > div {
	width: 320px; /* the width of the preview image */
	margin-bottom: 1em;
}
#streams ul {list-style-type: none; margin: 0; padding: 0; flex-grow: 1;}
#streams li {
	padding-left: 2em;
	text-indent: -2em;
}
.avatar {max-width: 40px;}
.inforow {display: flex;}
.inforow .img {flex-grow: 0; padding: 0.25em;}
.streamtitle {font-size: 85%;}
.emote {max-height: 1.25em;}
.tag {
	display: inline-block;
	padding: 0 0.125em; text-indent: 0; /* Override the general text-wrap settings from above */
	background: #ddd;
	border: 1px solid black;
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

.much_smaller     {border: 2px solid #bfe;}
.smaller          {border: 2px solid #cfe;}
.slightly_smaller {border: 2px solid #dfe;}
.samesize         {border: 2px solid #efe;}
.slightly_larger  {border: 2px solid #efd;}
.larger           {border: 2px solid #efc;}
.much_larger      {border: 2px solid #efb;}

#viewerlegend {display: flex;}
#viewerlegend div {margin-right: 0.5em; padding: 0.25em 0.125em;}

.magic-score {
	display: inline-block;
	min-width: 2em;
	text-align: end;
}
</style>

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
> <div id=viewerlegend>
> <div class=much_larger>Double</div>
> <div class=larger>50% more</div>
> <div class=slightly_larger>25% more</div>
> <div class=samesize>About the same</div>
> <div class=slightly_smaller>20% fewer</div>
> <div class=smaller>33% fewer</div>
> <div class=much_smaller>Half</div>
> </div>
{: tag=dialog #infodlg}

<script type=module src="$$static||raidfinder.js$$"></script>
