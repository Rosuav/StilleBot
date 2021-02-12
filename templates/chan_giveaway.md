# Channel points - giveaway manager

> <summary>Set up rewards</summary>
>
> <form id=configform>
> * <label>Cost per ticket: <input name=cost type=number value=1></label>
> * <label>Description: <input name=desc size=40 placeholder="Buy # tickets"> Put a <code>#</code> symbol for multibuy count</label>
> * <label>Multibuy options: <input name=multi size=40 placeholder="5 10 25 50"> List quantities that can be purchased</label>
> * <label>Max tickets: <input name=max type=number value=1> Purchases that would put you over this limit will be cancelled</label>
>
> <button>Save/reconfigure</button>
> </form>
{: tag=details}

<div id=existing></div>

<script type=module src="$$static||giveaway.js$$"></script>

<style>
details {border: 1px solid black; padding: 0.5em; margin: 0.5em;}
</style>
