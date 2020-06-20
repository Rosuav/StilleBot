import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, DIV, IMG, P, UL, LI, SPAN} = choc;
/* If no selected channel:

Fill out this form to prepare to monitor hype trains. Once you have the monitor
page, you can bookmark that exact page, and it'll always come back with the
correct setup.

* <label>Channel name: <input name=for width=20 required></label>
* Alert sound:
	<label><input type=radio name=alert value="" checked>(none)</label>
	<label><input type=radio name=alert value=ding>Ding</label>
	<label><input type=radio name=alert value=bipbipbip>Bip bip bip</label>
* <input type=submit value="Get link">


*/

//Uses your own clock in case it's not synchronized. Will be vulnerable to
//latency but not to clock drift/shift.
//When expiry < +new Date(), refresh the page automatically.
let expiry;
function update() {
	let tm = Math.floor((expiry - +new Date()) / 1000);
	//TODO: If t <= 0, update stuff. Also if cooldown is over, optionally play a sound.
	let t = ":" + ("0" + (tm % 60)).slice(-2);
	if (tm >= 3600) t = Math.floor(tm / 3600) + ("0" + (Math.floor(tm / 60) % 60)).slice(-2) + ":" + t;
	else t = Math.floor(tm / 60) + t; //Common case - less than an hour
	document.getElementById("time").innerHTML = t;
}

function subs(n) {return Math.floor((n + 499) / 500);} //Calculate how many T1 subs are needed

function render(state) {
	let goal;
	if (state.expires)
	{
		//Active hype train!
		goal = `Level ${state.level} requires ${state.goal} bits or ${subs(state.goal)} tier one subs.`;
		let need = state.goal - state.total;
		if (need < 0) goal += " TIER FIVE COMPLETE!";
		else goal += ` Need ${need} more bits or ${subs(need)} more subs.`;
		//TODO: Show the emotes you could get at current level and next level
		//And then fall through
	}
	if (state.expires || state.cooldown)
	{
		expiry = +new Date() + (state.expires || state.cooldown) * 1000;
		set_content("#status", [
			P({className: "countdown"}, [
				goal ? "HYPE TRAIN ACTIVE! " : "The cookies are in the oven. ",
				SPAN({id: "time"})
			]),
			goal && P({id: "goal"}, goal),
		]);
		update(); setInterval(update, 1000);
	}
	else set_content("#status", [
		P({className: "countdown"}, "Cookies are done!"),
	]);
}
console.log(window.state)
render(window.state);
