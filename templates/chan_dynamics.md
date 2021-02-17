# Channel points - dynamic rewards

Title | Base cost | Formula | Current cost | Actions
------|-----------|---------|--------------|--------
-     | -         | -       | -            | (loading...)
{: #rewards}

<button type=button id=add>Add dynamic reward</button> Copy from: <select id=copyfrom><option value="-1">(none)</option></select>

Choose how the price grows by setting a formula, for example:
* `PREV * 2` (double the price every time)
* `PREV + 500` (add 500 points per purchase)
* `PREV * 2 + 1500` (double it, then add 1500 points)

Rewards will reset to base price whenever the stream starts, and will be automatically
put on pause when the stream is offline. Note that, due to various delays, it's best to
have a cooldown on the reward itself - at least 30 seconds - to ensure that two people
can't claim the reward at the same price.

[Configure reward details here](https://dashboard.twitch.tv/viewer-rewards/channel-points/rewards)

<script type=module src="$$static||dynamics.js$$"></script>

<style>
input[type=number] {width: 4em;}
code {background: #ffe;}
</style>
