# $$title||Followed streams$$$$auxtitle||$$

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
>
> Content Classification Labels | Notify | Warn | Blur thumbnail | Suppress
> ------------------------------|--------|------|----------------|----------
$$ccl_options||> - | - | - | - | (not available)$$
> {: #prefs_ccls}
>
{: tag=dialog #tags}

<button class=opendlg data-dlg=infodlg>Legend/info</button> <button id=highlights>Edit highlight list</button>
<button id=allraids>All recent raids</button> <button id=tagprefs>Preferences</button>
<button id=mydetails>This stream's info</button>

* $$sortorders$$
{: #sort}

<div id=streams class="streamtiles sizeborders"></div>

> <span id=notes_about_channel>Channel name: </span>
>
> <form method=dialog>
> <textarea rows=8 cols=50></textarea>
> <button value="save">Save</button> <button value="cancel">Cancel</button>
> </form>
{: tag=dialog #editnotes}

<a id=yourcat href="#" target="_blank">Current category: ??</a><br>$$catfollow||$$
[Channels you follow](raidfinder)

> ### Raids to or from this channel:
> <label><input type=checkbox checked id=show-outgoing> Outgoing</label> <label><input type=checkbox checked id=show-incoming> Incoming</label>
> <ul></ul>
{: tag=dialog #raids}

<!-- -->

> ### Legend/info
> This raid finder shows the people you currently follow, and helps you select someone<br>
> to raid. Incoming and outgoing raids $$is_tracked||will be shown if Mustard Mine tracks this channel$$.
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
> <span id=ccls_in_use></span>
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
> <p id=raiderror hidden></p>
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

<!-- -->

> ### Follow categories
>
> <span id=actiondesc>Follow/unfollow these categories:</span>
> <div id=catlist></div>
>
> [Confirm](:#confirmfollowcategory) [Cancel](:.dialog_close)
{: tag=dialog #followcategorydlg}
