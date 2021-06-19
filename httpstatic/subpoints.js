const ComfyJS = window.ComfyJS;

const target = document.getElementById("display");
export function render(data) {
	target.innerHTML = data.points + " / " + (data.goal || "1234");
}

if (ComfyJS && window.channelname !== "") {
	ComfyJS.onSub = ComfyJS.onResub = ComfyJS.onSubGift = ComfyJS.onSubMysteryGift = function () {
		ws_sync.send({cmd: "refresh"});
	};
	ComfyJS.Init(window.channelname);
}
