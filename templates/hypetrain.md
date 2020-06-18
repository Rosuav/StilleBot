# Hype train status

$$status$$ <span id=time></span>
{:#countdown}

$$goal$$
{:#goal}

<style>
#countdown {
	font-size: 250%;
}
</style>

<script>
//Uses your own clock in case it's not synchronized. Will be vulnerable to
//latency but not to clock drift/shift.
//When expiry < +new Date(), refresh the page automatically.
const target = $$target$$;
const expiry = +new Date() + target * 1000;
function update() {
	let tm = Math.floor((expiry - +new Date()) / 1000);
	let t = ":" + ("0" + (tm % 60)).slice(-2);
	if (tm >= 3600) t = Math.floor(tm / 3600) + ("0" + (Math.floor(tm / 60) % 60)).slice(-2) + t;
	else t = Math.floor(tm / 60) + t; //Common case - less than an hour
	document.getElementById("time").innerHTML = t;
}
if (target) {update(); setInterval(update, 1000);}
</script>
