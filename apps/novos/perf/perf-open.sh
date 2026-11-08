#!/bin/sh
# TV side of perf-on-tv.sh: one opening of the uploaded preview, with the CPU time and the
# memory of surface-manager before and after. luna-send needs a terminal (ssh -tt).
#
# Usage: perf-open.sh <app id> <main url> <page or ""> <seconds open>
# Prints one line: result launch=<ms> stop=<ms> cpu_ticks=<n> rss_before=<kB> …
app=$1
main=$2
page=$3
seconds=$4

ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
pid=$(pidof surface-manager | cut -d' ' -f1)
ticks() { set -- $(cat /proc/"$pid"/stat); echo $(( ${14} + ${15} )); }
rss() { awk '/VmRSS/ { print $2 }' /proc/"$pid"/status; }

params='{}'
[ -z "$page" ] || params='{"page":"'"$page"'"}'
close='{"appId":"'"$app"'"}'

luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId "$close" >/dev/null 2>&1
sleep 1
ticks0=$(ticks)
rss0=$(rss)
start=$(ms)
luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/launch \
    '{"appId":"'"$app"'","main":"'"$main"'","params":'"$params"'}' >/dev/null 2>&1
sleep "$seconds"
ticks1=$(ticks)
rss1=$(rss)
stop=$(ms)
luna-send -n 1 -w 5000 luna://com.webos.service.systemUIManager/closeByAppId "$close" >/dev/null 2>&1
# The probe writes its file shortly after the window closed.
sleep 2
echo "result launch=$start stop=$stop cpu_ticks=$((ticks1 - ticks0)) rss_before=$rss0 rss_open=$rss1 rss_after=$(rss)"
