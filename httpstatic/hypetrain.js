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

//The threshold for "Super Hard" is this many bits per level (not total).
//In order to unlock the sixth emote for each level, you need to have a
//goal that is at least this number of bits for the level (since Insane
//is even higher - level 1 needs 10,000 bits).
const hardmode = [0, 5000, 7500, 10600, 14600, 22300];

//window.channelid has our crucial identifier

let expiry, updating = null;
function update() {
	let tm = Math.floor((expiry - +new Date()) / 1000);
	const time = document.getElementById("time");
	if (tm <= 0 || !time) {
		clearInterval(updating); updating = null;
		if (time) time.innerHTML = "";
		refresh();
		return;
	}
	let t = ":" + ("0" + (tm % 60)).slice(-2);
	if (tm >= 3600) t = Math.floor(tm / 3600) + ("0" + (Math.floor(tm / 60) % 60)).slice(-2) + ":" + t;
	else t = Math.floor(tm / 60) + t; //Common case - less than an hour
	time.innerHTML = t;
}

function subs(n) {return Math.floor((n + 499) / 500);} //Calculate how many T1 subs are needed

function fmt_contrib(c) {
	if (c.type === "BITS") return `${c.display_name} with ${c.total} bits`;
	return `${c.display_name} with ${c.total / 500} T1 subs (or equivalent)`;
}

//TODO: Play an audio snippet, if configured to do so
function hypetrain_started() {console.log("Starting a hype train!");}
function cooldown_ended() {console.log("Cookies are done!");}

let last_rendered = null;
function render(state) {
	state.cooldown = +new Date() / 1000 + 100;
	//Show the emotes that we could win (or could have won last hype train)
	const lvl = state.cooldown && state.level; //If not active or cooling down, hide 'em all
	document.querySelectorAll("#emotes li").forEach((li, idx) => li.className =
		lvl >= idx + 2 || state.total >= state.goal ? "available" :
		state.expires && lvl === idx + 1 ? "next" : ""); //Only show "next" during active hype trains

	if (!state.expires && !state.cooldown) {
		//Idle state. If we previously had a cooldown, it's now expired.
		set_content("#status", [
			P({className: "countdown"}, "Cookies are done!"),
			//Note that we might not have conductors (or any data). It lasts a few days at most.
		]);
		document.querySelectorAll("#emotes li").forEach(li => li.className = "");
		if (last_rendered === "cooldown") cooldown_ended();
		last_rendered = "idle";
		return;
	}
	let goal;
	if (state.expires)
	{
		//Active hype train!
		goal = `Level ${state.level} requires ${state.goal} bits or ${subs(state.goal)} tier one subs.`;
		let need = state.goal - state.total;
		if (need < 0) goal += " TIER FIVE COMPLETE!";
		else goal += ` Need ${need} more bits or ${subs(need)} more subs.`;
		document.getElementById("emotes").classList.toggle("hardmode", state.goal >= hardmode[state.level]);
		if (last_rendered === "idle") hypetrain_started();
		last_rendered = "active";
	}
	else
	{
		if (state.level === 1)
			goal = `The last hype train reached ${state.total} out of ${state.goal} to complete level 1.`;
		else if (state.level === 5 && state.total >= state.goal)
			goal = `The last hype train finished level 5 at ${Math.round(100 * state.total / state.goal)}%!!`;
		else
			goal = `The last hype train completed level ${state.level - 1}! Good job!`;
		last_rendered = "cooldown"; //No audio cue when changing from active to cooldown
	}
	expiry = (state.expires || state.cooldown) * 1000;
	set_content("#status", [
		P({className: "countdown"}, [
			state.expires ? "HYPE TRAIN ACTIVE! " : "The hype train is on cooldown. Next one can start in ",
			SPAN({id: "time"})
		]),
		P(["Hype conductors: ", state.conductors.map(fmt_contrib).join(", and ")]),
		P(["Latest contribution: ", fmt_contrib(state.lastcontrib)]),
		P(goal),
	]);
	if (updating) clearInterval(updating);
	updating = setInterval(update, 1000);
	update();
}

let socket;
const protocol = window.location.protocol == "https:" ? "wss://" : "ws://";
function connect()
{
	socket = new WebSocket(protocol + window.location.host + "/ws");
	socket.onopen = () => {
		console.log("Socket connection established.");
		socket.send(JSON.stringify({cmd: "init", type: "hypetrain", group: window.channelid}));
	};
	socket.onclose = () => {
		socket = null;
		console.log("Socket connection lost.");
		setTimeout(connect, 250);
	};
	socket.onmessage = (ev) => {
		let data = JSON.parse(ev.data);
		console.log("Got message from server:", data);
		if (data.cmd === "update") render(data);
	};
}
if (window.channelid) connect();
else set_content("#status", "Need a channel name (TODO: have a form)");

//TODO: Call this automatically when the timer expires, but don't get stuck in a loop
//This isn't needed most of the time (the webhook will signal us), but can help if
//anonymous events happen and are missed by the hook.
function refresh() {
	if (socket) return socket.send(JSON.stringify({cmd: "refresh"}));
	//Should we try to reconnect the socket w/o reloading?
	window.location.reload();
};
DOM("#refresh").onclick = refresh;
