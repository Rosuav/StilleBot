# Emotes available to the bot

<style>
p {max-width: 80em; padding: 0.25em;}
.highlight {background-color: #dfd; border: 1px solid green;}
img {cursor: pointer;}
#picker {
	position: sticky;
	top: 0.5em;
	border: 1px solid blue;
	background: white;
}
#emotes {
	display: inline-block;
	min-height: 28px;
}
#emotenames {box-sizing: border-box; width: 100%;}
</style>

Emotes highlighted in this way can be relied upon more than non-highlighted emotes,
as they come from permanent subscriptions. They may be removed or altered by their
creators, but should not expire on their own.
{: .highlight}

Unhighlighted emotes may disappear
from the bot at any time, but can be restored with a gift subscription.

Selected emotes - click emotes to add them, then copy/paste the images or
emote names<br><input id=emotenames readonly><br>
<span id=emotes></span>
{: #picker}

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
