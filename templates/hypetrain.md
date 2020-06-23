# Train Tracks

<div id=status></div>

<button type=button id=refresh>Refresh</button>

NOTE: Anonymous events will not be reported here (as of June 2020 - this may
change in the future). If an anonymous cheer or sub causes the hype train to
advance to the next level, you may need to click Refresh to see it, or wait
for a non-anonymous event afterwards. (The anonymous event WILL be counted in
the total progression.)

Note also that broadcaster actions do not affect hype trains at all - you can't
start a hype train for yourself, nor can you progress it. Except for the sneaky
loophole of anonymity, of course...

$$emotes$$
{:#emotes}

[Check which hype emotes you have](/checklist)

<style>
#countdown {
	font-size: 250%;
}
#emotes li img:last-of-type {display: none;}
#emotes.hardmode li img:last-of-type {display: inline-block;}
#emotes li.available:before {content: "Earnable: ";}
#emotes li.next:before {content: "Next goal: ";}
#emotes li:not(.next):not(.available) {display: none;}
</style>

<script>window.channelid = $$channelid$$;</script>
<script type=module src="/static/hypetrain.js"></script>
