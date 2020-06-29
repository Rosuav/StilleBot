# Sub points counter

$$points$$
{:#points}

[Add this link to OBS to show this counter](/subpoints?view=$$nonce$$)<input type=hidden name=nonce value="$$nonce$$"><br>
Unpaid sub points (eg bot): <input name=unpaidpoints type=number value="$$unpaidpoints$$"><br>
Goal (eg points for next emote): <input name=goal type=number value="$$goal$$"><br><input type=submit value="Save">
{:.cfg}

<style>
$$style$$
</style>

<script>window.nonce = "$$viewnonce$$";</script>
<script type=module src="/static/subpoints.js"></script>
