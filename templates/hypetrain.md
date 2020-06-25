# Train Tracks

<div id=status></div>

<button type=button id=refresh>Refresh</button>

$$emotes$$
{:#emotes}

[Check which hype emotes you have](/checklist)

<button type=button id=configure>Configure</button>

NOTE: Anonymous events will not be reported here (as of June 2020 - this may
change in the future). If an anonymous cheer or sub causes the hype train to
advance to the next level, you may need to click Refresh to see it, or wait
for a non-anonymous event afterwards. (The anonymous event WILL be counted in
the total progression.)

Note also that broadcaster actions do not affect hype trains at all - you can't
start a hype train for yourself, nor can you progress it. Except for the sneaky
loophole of anonymity, of course...

<style>
#countdown {
	font-size: 250%;
}
#emotes li img:last-of-type {display: none;}
#emotes.hardmode li img:last-of-type {display: inline-block;}
#emotes li.available:before {content: "Earnable: ";}
#emotes li.next:before {content: "Next goal: ";}
#emotes li:not(.next):not(.available) {display: none;}
audio {display: none;}
#config li {margin-bottom: 1.5em;}
</style>

<script>window.channelid = $$channelid$$;</script>
<script type=module src="/static/hypetrain.js"></script>

> <button type=button class=dialog_cancel>x</button>
>
> Train Track configuration <!-- that sounds like something completely different -->
>
> TODO: Default channel?
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
>
> <p><button type=button id=savecfg>Save</button> <button type=button class=dialog_close>Cancel</button></p>
>
{: tag=dialog #config}

<audio id=sfx_start controls src="/static/whistle.flac" preload="none"></audio>
<audio id=sfx_insistent controls src="/static/insistent.flac" preload="none"></audio>
<audio id=sfx_ding controls src="/static/ding.mp3" preload="none"></audio>
