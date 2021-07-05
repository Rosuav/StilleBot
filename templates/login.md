# Please log in

This page requires $$msg||Twitch authentication$$. Click the button below to do that!

[Log in with Twitch](: #twitchlogin)

<script>
document.getElementById("twitchlogin").onclick = async e => {
	const data = await (await fetch("/twitchlogin?urlonly=true&scope=" + encodeURIComponent("$$scopes||$$"))).json();
	window.open(data.uri, "login", "width=525, height=900");
}
</script>
