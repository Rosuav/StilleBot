# Automated commands for $$channel$$

$$messages$$

Specify the time as `50-60` to mean a random range of times, or as `14:40` to mean that
exact time (in your timezone). Automated commands will be sent only if the channel is
online at that time.

NOTE: For greater flexibility and easier management, create a command and have it set to
automatically run itself. This can be done through the regular [command editor](commands);
double-click a command's yellow "When..." box to configure this.

> Frequency | Command | Output |
> ----------|---------|--------|-
> $$repeats$$
{:tag=form method=post}

$$save_or_login||$$

Create new autocommands with [!repeat](https://rosuav.github.io/StilleBot/commands/repeat)
and remove them with [!unrepeat](https://rosuav.github.io/StilleBot/commands/repeat).
Autocommands can either display text, or execute a command. It's usually easiest to tie
each autocommand to an [echo command](commands).
