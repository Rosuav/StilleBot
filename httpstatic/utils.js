//Usage:
//import {...} from "$$static||utils.js$$";

export function waitlate(wait_time, late_time, confirmdesc, callback) {
	//Assumes that this is attached to a button click. Other objects
	//and other events may work but are not guaranteed.
	let wait = 0, late = 0, timeout = 0, btn, orig;
	function reset() {
		clearTimeout(timeout);
		set_content(btn, orig).disabled = false;
		wait = late = timeout = 0;
	}
	return e => {
		if (btn && btn !== e.match) reset();
		const t = +new Date;
		if (t > wait && t < late) {
			reset();
			callback(e);
			return;
		}
		wait = t + wait_time; late = t + late_time;
		btn = e.match; orig = btn.innerText;
		setTimeout(() => btn.disabled = false, wait_time);
		timeout = setTimeout(reset, late_time);
		set_content(btn, confirmdesc).disabled = true;
	};
}

const login = document.getElementById("twitchlogin");
if (login) login.onclick = async e => {
	const data = await (await fetch("/twitchlogin?urlonly=true&scope=" + login_scope)).json();
	window.open(data.uri, "login", "width=525, height=900");
}
