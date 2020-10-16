# Sub points counter

$$points$$
{:#points}

<form method=post class=cfg>
[Add this link to OBS to show this counter](/subpoints?view=$$nonce$$)<input type=hidden name=nonce value="$$nonce$$"><br>
Unpaid sub points (eg bot): <input name=unpaidpoints type=number value="$$unpaidpoints$$"><br>
Font (from Google Fonts): <input name=font value="$$font$$"> <input type=number name=fontsize value="$$size$$"> (changing this requires a refresh of the in-OBS page)<br>
Goal (eg points for next emote): <input name=goal type=number value="$$goal$$"><br><label>Use chat notifications (more reliable but might take a little CPU and bandwidth) <input type=checkbox name=usecomfy$$usecomfy$$></label><br><input type=submit value="Save">
</form>

<style>
$$style$$
</style>

<script>window.nonce = "$$viewnonce$$"; window.channelname = "$$channelname$$";</script>
$$comfy$$
<script type=module src="/static/subpoints.js"></script>
