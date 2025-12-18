# Train Tracks
## $$channelname$$ hype train

<div id=hypeinfo><p id=status>$$loading$$</p></div>

WARNING: Audio alerts may not play if you have not interacted with the page.
Click anywhere to enable alerts.
{:#interact-warning .hidden}

$$nojs||<button type=button id=refresh>Refresh</button>$$

$$emotes$$
{:.emotelevels #emotes}

<!-- -->

* The Golden Kappa: ![Kappa](https://static-cdn.jtvnw.net/emoticons/v2/80393/default/light/1.0)*![Kappa](https://static-cdn.jtvnw.net/emoticons/v2/80393/default/light/3.0)*
{:.emotelevels #goldenkappa}

[Check which hype emotes you have](/checklist)

$$nojs||<button type=button id=configure>Configure</button>$$

NOTE: Anonymous events will not be reported here (as of June 2020 - this may
change in the future). If an anonymous cheer or sub causes the hype train to
advance to the next level, you may need to click Refresh to see it, or wait
for a non-anonymous event afterwards. (The anonymous event WILL be counted in
the total progression.)

Note also that broadcaster actions do not affect hype trains at all - you can't
start a hype train for yourself, nor can you progress it. Except for the sneaky
loophole of anonymity, of course...

Please note that while this site will advise whether there is a cool down in
effect (and of course provide useful information when a Hype Train is in process),
there is currently no way of advising whether a Streamer has disabled Hype Trains
for their stream, the number of actions required to trigger it, or the difficulty
level to which it has been set (although this can be deduced during a hype train,
it cannot be seen outside of one).

<form method=get action=hypetrain>
<label>Select channel: <input name=for></label>
<input type=submit value="Go">
</form>

<style>
@import url('https://fonts.googleapis.com/css2?family=Inter&display=swap');
#hypeinfo {font-family: 'Inter', sans-serif;}
.cookiesinfo {
	color: black;
	text-decoration: none;
}
.cookiesinfo:after {
	content: "?";
	font-family: sans-serif;
	display: inline-block;
	text-align: center;
	font-size: 0.8em;
	line-height: 0.8em;
	border-radius: 50%;
	margin-left: 6px;
	padding: 0.13em 0.2em 0.09em 0.2em;
	border: 1px solid;
}

.avatar {max-width: 40px; vertical-align: middle;}

.emotelevels li:before {content: "Pending: ";}
.emotelevels li.available:before {content: "Earnable: ";}
.emotelevels li.next:before {content: "Next goal: ";}
#emotes li:last-of-type:before {content: "";} /* The last row isn't a single level */
body:not(.emotes_allrows) #emotes li:not(.next):not(.available) {display: none;}

/* During a golden kappa train, hide the regular emotes and just show the one row with one emote. */
#goldenkappa {display: none;}
[data-hypetype=golden_kappa] #goldenkappa {display: block;}
[data-hypetype=golden_kappa] #emotes {display: none;}

/* Show a larger version of the emotes on hover */
.emotelevels em {
	position: relative;
	width: 0; height: 0;
}
.emotelevels em:nth-of-type(1) {left: 30px;} /* Manually do the calculations :( */
.emotelevels em:nth-of-type(2) {left: 60px;}
.emotelevels em:nth-of-type(3) {left: 90px;}
.emotelevels em:nth-of-type(4) {left: 120px;}
.emotelevels em:nth-of-type(5) {left: 150px;}
.emotelevels em:nth-of-type(6) {left: 180px;}
.emotelevels em:nth-of-type(7) {left: 210px;}
.emotelevels em:nth-of-type(8) {left: 240px;}
.emotelevels em:nth-of-type(9) {left: 270px;}
.emotelevels em:nth-of-type(10) {left: 300px;}
.emotelevels em:nth-of-type(11) {left: 330px;}
.emotelevels em:nth-of-type(12) {left: 360px;}
.emotelevels em img {
	display: none;
	position: absolute;
	background: white;
	border: 2px solid black;
	box-shadow: 5px 5px 10px 0px cyan;
	padding: 2px;
	margin: 2px;
}
.emotelevels img:hover + em img {display: block;}

/* With class emotes_large, show those larger-format ones instead of the small ones. No hover. */
.emotes_large .emotelevels img {display: none;}
.emotes_large .emotelevels li {height: 280px;}
.emotes_large .emotelevels li:last-of-type {height: 140px;} /* The last row (or the only row for Golden Kappa) doesn't need to wrap */
.emotes_large .emotelevels em img {display: block; box-shadow: none; border: none;}
.emotes_large .emotelevels em:nth-of-type(1) {left: 0px;} /* Reposition since we have to do it manually anyway :( */
.emotes_large .emotelevels em:nth-of-type(2) {left: 125px;}
.emotes_large .emotelevels em:nth-of-type(3) {left: 250px;}
.emotes_large .emotelevels em:nth-of-type(4) {left: 375px;}
.emotes_large .emotelevels em:nth-of-type(5) {left: 500px;}
.emotes_large .emotelevels em:nth-of-type(6) {left: 625px;}
/* If Twitch rolls out a twelfth emote for each row, reset these to start at zero instead of staggering them. */
/* CJA 20251219: They did. If we go back to an odd number, move one up and go back to starting at 62.5px. */
.emotes_large .emotelevels em:nth-of-type(7) {top: 118px; left: 0px;}
.emotes_large .emotelevels em:nth-of-type(8) {top: 118px; left: 125px;}
.emotes_large .emotelevels em:nth-of-type(9) {top: 118px; left: 250px;}
.emotes_large .emotelevels em:nth-of-type(10) {top: 118px; left: 375px;}
.emotes_large .emotelevels em:nth-of-type(11) {top: 118px; left: 500px;}
.emotes_large .emotelevels em:nth-of-type(12) {top: 118px; left: 625px;}

audio {display: none;}
#config ul.gapbelow li {margin-bottom: 1.5em;}
#interact-warning {
	background: #ffff88;
	border: 3px solid #ffaa00;
	width: max-content;
	padding: 0.5em;
}
#interact-warning.hidden {display: none;}

#infopopup {max-width: 680px;}

#hypeinfo p {
	padding: 1em;
	margin: 0.5em;
	max-width: 40em;
	border: 1px dashed blue;
}
</style>

> ### Train Track configuration <!-- that sounds like something completely different -->
> <form id=configform>
> [Log in to save preferences](:.twitchlogin)
>
> * <label><input type=checkbox name=use_start> Play sound on hype train start</label><br>
>   Volume <input type=range name=vol_start value=100><br>
>   <button type=button class="play" id="play_start">&#x25b6;</button>
>   CC-BY-3.0 audio clip from [Freesound](https://freesound.org/people/ecodios/sounds/119963/)
> * <label><input type=checkbox name=use_insistent> Play insistent sound on end of cooldown</label><br>
>   Volume <input type=range name=vol_insistent value=100><br>
>   <button type=button class="play" id="play_insistent">&#x25b6;</button>
>   CC-BY-3.0 audio clip from [Freesound](https://freesound.org/people/tim.kahn/sounds/22627/)
> * <label><input type=checkbox name=use_ding> Play ding sound on end of cooldown</label><br>
>   Volume <input type=range name=vol_ding value=100><br>
>   <button type=button class="play" id="play_ding">&#x25b6;</button>
>   CC-0 audio clip from [Freesound](https://freesound.org/people/ccr_fs/sounds/484718/)
> {: .gapbelow}
>
> <hr>
>
> Emote display:
> * <label><input type=checkbox name=emotes_large>Large format</label>
> * <label><input type=checkbox name=emotes_allrows>Keep all rows visible</label>
>
> [Save](:#save_prefs type=submit) [Cancel](:.dialog_close)
> </form>
{: tag=dialog #config}

<dialog id=infopopup><button type=button class=dialog_cancel>x</button><div></div></dialog>

<audio id=sfx_start controls src="/static/whistle.flac" preload="none"></audio>
<audio id=sfx_insistent controls src="/static/insistent.flac" preload="none"></audio>
<audio id=sfx_ding controls src="/static/ding.mp3" preload="none"></audio>
