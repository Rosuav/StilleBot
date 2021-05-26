# $$giveaway_title||Channel points - giveaway manager$$

<div id=master_status>Loading giveaway status...</div>

<ul id=ticketholders></ul>

> <summary>Set up rewards</summary>
>
> <form id=configform>
> * <label>Giveaway title: <input name=title size=40 placeholder="Win an awesome thing!"></label>
> * <label>Cost per ticket: <input name=cost type=number min=1 value=1></label>
> * <label>Description: <input name=desc size=40 placeholder="Buy # tickets"> Put a <code>#</code> symbol for multibuy count</label>
> * <label>Multibuy options: <input name=multi size=40 placeholder="1 5 10 25 50"> List quantities that can be purchased (always include 1!)</label>
> * <label>Max tickets: <input name=max type=number min=0 value=1> Purchases that would put you over this limit will be cancelled</label>
> * <label>Redemption hiding:
>   <select name=pausemode><option value="disable">Disable, hiding them from users</option><option value="pause">Pause and leave visible</option></select>
>   When there's no current giveaway, should redemptions remain visible (but unpurchaseable), or vanish entirely?
>   </label>
> * <label><input type=checkbox name=allow_multiwin value=yes> Allow òne person to win multiple times? If not, the winner's tickets will be automatically removed.</label>
> * <label>Time before giveaway closes: <input name=duration type=number min=0 max=3600> (seconds) How long should the giveaway be open? 0 leaves it until explicitly closed.</label>
>
> <button>Save/reconfigure</button>
> </form>
{: tag=details}

[Master Control](:#showmaster)

> ### Master Control
> * [Open giveaway](:.master #open) and allow people to buy tickets
> * [Close giveaway](:.master #close) so no more tickets will be bought
> * [Choose winner](:.master #pick) and remove that person's tickets
> * [Cancel and refund](:.master #cancel) all points spent on tickets
> * [End giveaway](:.master #end) clearing out tickets
>
{: tag=dialog #master}

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
