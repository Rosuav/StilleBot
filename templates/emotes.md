# Emotes available to the bot

<style>
p {max-width: 80em;}
.highlight {background-color: #dfd; border: 1px solid green;}
img {cursor: pointer;}
#picker {
	position: fixed;
	top: 0; right: 0;
	border: 1px solid blue;
	margin: 0.5em;
	padding: 0.25em;
	background: white;
	max-width: 18em;
}
#emotes {
	display: inline-block;
	min-height: 28px;
}
</style>

Selected emotes - click to add, then copy/paste the images or emote names<br><input id=emotenames readonly size=42><br>
<span id=emotes></span>
{: #picker}

Emotes highlighted in this way can be relied upon more than non-highlighted emotes,
as they come from permanent subscriptions. They may be removed or altered by their
creators, but should not expire on their own.
{: .highlight}

Unhighlighted emotes may disappear
from the bot at any time, but can be restored with a gift subscription.

$$emotes$$

$$save$$

<script>
document.body.onclick = e => {
	const img = e.target; if (img.tagName != "IMG") return;
	console.log(img.alt, img.src);
	document.getElementById("emotenames").value += img.alt + " ";
	const em = document.getElementById("emotes");
	em.appendChild(img.cloneNode());
	em.appendChild(document.createTextNode(" ")); //Mainly for the copy/paste
};
</script>
