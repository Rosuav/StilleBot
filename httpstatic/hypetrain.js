import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, DIV, IMG, P, UL, LI, SPAN} = choc;

//The threshold for "Super Hard" is this many bits per level (not total).
//In order to unlock the sixth emote for each level, you need to have a
//goal that is at least this number of bits for the level (since Insane
//is even higher - level 1 needs 10,000 bits).
const hardmode = [0, 5000, 7500, 10600, 14600, 22300];

let config = {};
try {config = JSON.parse(localStorage.getItem("hypetrain_config")) || {};} catch (e) {}
const el = DOM("form").elements;
for (let name in config) {
	const [type, which] = name.split("_");
	const audio = DOM("#sfx_" + which);
	if (type === "use") {el[name].checked = true; audio.preload = "auto";}
	else if (type === "vol") {el[name].value = config[name]; audio.volume = config[name] / 100;}
	//That should be all the configs that get saved
}

//window.channelid has our crucial identifier

let socket; //temporarily up here to allow an encapsulation violation

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
	if (tm >= 3600) t = Math.floor(tm / 3600) + ":" + ("0" + (Math.floor(tm / 60) % 60)).slice(-2) + t;
	else t = Math.floor(tm / 60) + t; //Common case - less than an hour
	time.innerHTML = t;
}

function subs(n) {return Math.floor((n + 499) / 500);} //Calculate how many T1 subs are needed

function fmt_contrib(c) {
	if (c.type === "BITS") return `${c.display_name} with ${c.total} bits`;
	return `${c.display_name} with ${c.total / 500} T1 subs (or equivalent)`;
}

//Play audio snippets, if configured to do so
function play(which, force) {
	const el = DOM("#sfx_" + which);
	if (el.playing) return; //Don't stack audio
	if (!config["use_" + which] && !force) return; //Play if configured (or if testing)
	const playing = el.play();
	if (playing) playing.catch(err => {
		//Autoplay was denied. Notify the server for debugging purposes.
		//Violates encapsulation. FIXME: Either do this properly or don't.
		console.error("Unable to autoplay");
		console.error(err);
		if (socket) socket.send(JSON.stringify({cmd: "reporterror", context: "autoplay", error: err.name, msg: err.message}));
	});
	if (which === "insistent") {
		el.loop = true;
		setTimeout(() => el.loop = false, force ? 2500 : 9500);
	}
}
function hypetrain_started() {play("start");}
function cooldown_ended() {play("ding"); play("insistent");}

let last_rendered = null;
function render(state) {
	//Show the emotes that we could win (or could have won last hype train)
	const lvl = state.cooldown && state.level; //If not active or cooling down, hide 'em all
	document.querySelectorAll("#emotes li").forEach((li, idx) => li.className =
		lvl >= idx + 2 || state.total >= state.goal ? "available" :
		state.expires && lvl === idx + 1 ? "next" : ""); //Only show "next" during active hype trains
	document.getElementById("emotes").classList.toggle("hardmode", state.goal >= hardmode[state.level]);

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

//~ let socket;
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
		if (data.cmd === "hit-it") play("ding", 1);
	};
}
if (window.channelid) connect();
else set_content("#status", "Need a channel name (TODO: have a form)");

//This isn't needed most of the time (the webhook will signal us), but can help if
//anonymous events happen and are missed by the hook.
function refresh() {
	if (socket) return socket.send(JSON.stringify({cmd: "refresh"}));
	//Should we try to reconnect the socket w/o reloading?
	window.location.reload();
};
DOM("#refresh").onclick = refresh;

DOM("#configure").onclick = () => DOM("#config").showModal();

on("click", ".play", e => {
	play(e.match.id.split("_")[1], 1);
});
on("input", 'input[type="range"]', e => {
	const which = "#sfx_" + e.match.name.split("_")[1];
	DOM(which).volume = e.match.value / 100;
});
DOM("#savecfg").onclick = e => {
	config = {}; new FormData(DOM("form")).forEach((v,k) => config[k] = v);
	localStorage.setItem("hypetrain_config", JSON.stringify(config));
	DOM("#config").close();
};

//Compat shim lifted from Mustard Mine
//For browsers with only partial support for the <dialog> tag, add the barest minimum.
//On browsers with full support, there are many advantages to using dialog rather than
//plain old div, but this way, other browsers at least have it pop up and down.
document.querySelectorAll("dialog").forEach(dlg => {
	if (!dlg.showModal) dlg.showModal = function() {this.style.display = "block";}
	if (!dlg.close) dlg.close = function() {this.style.removeProperty("display");}
});
on("click", ".dialog_cancel,.dialog_close", e => e.match.closest("dialog").close());
