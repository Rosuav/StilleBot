# Channel points - giveaway manager

<div id=master_status>Loading giveaway status...</div>

<ul id=ticketholders></ul>

> <summary>Set up rewards</summary>
>
> <form id=configform>
> * <label>Cost per ticket: <input name=cost type=number value=1></label>
> * <label>Description: <input name=desc size=40 placeholder="Buy # tickets"> Put a <code>#</code> symbol for multibuy count</label>
> * <label>Multibuy options: <input name=multi size=40 placeholder="1 5 10 25 50"> List quantities that can be purchased (always include 1!)</label>
> * <label>Max tickets: <input name=max type=number value=1> Purchases that would put you over this limit will be cancelled</label>
> * <label>Redemption hiding:
>   <select name=pausemode><option value="disable">Disable, hiding them from users</option><option value="pause">Pause and leave visible</option></select>
>   When there's no current giveaway, should redemptions remain visible (but unpurchaseable), or vanish entirely?
>   </label>
>
> <button>Save/reconfigure</button>
> </form>
{: tag=details}

<button type=button id=showmaster>Master Control</button>

> <h3>Master Control</h3>
>
> * <button type=button class="master open">Open giveaway</button> and allow people to buy tickets
> * <button type=button class="master close">Close giveaway</button> so no more tickets will be bought
> * TODO: Timed giveaways where it automatically closes after X seconds/minutes
> * <button type=button class="master pick">Choose winner</button> and remove that person's tickets
> * <button type=button class="master cancel">Cancel and refund</button> all points spent on tickets
> * <button type=button class="master end">End giveaway</button> clearing out tickets
>
{: tag=dialog #master}

<script type=module src="$$static||giveaway.js$$"></script>

<div id=existing></div>

<style>
details {border: 1px solid black; padding: 0.5em; margin: 0.5em;}
#master li {
	margin-top: 0.5em;
	margin-right: 40px;
	list-style-type: none;
}
#master_status {
	width: 350px;
	background: aliceblue;
	border: 3px solid blue;
	margin: auto;
	padding: 1em;
	font-size: 125%;
}
#master_status.is_open {
	background: #a0f0c0;
	border-color: green;
}
#master_status h3 {
	font-size: 125%;
	margin: 0 auto 0.5em;
}
.winner_name {
	background-color: #ffe;
	font-weight: bold;
}
</style>
