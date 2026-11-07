#!/bin/bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -n ${TMPDIR:-} ]] || { echo "FAIL F1 стенд: TMPDIR не задан"; exit 2; }
WORK=$(mktemp -d "$TMPDIR/plasma-fan-tests.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

fail_setup() { echo "FAIL F1 стенд: $*"; exit 2; }
command -v bwrap >/dev/null || fail_setup "bwrap не найден"
command -v node >/dev/null || fail_setup "node не найден"
BWRAP=$(command -v bwrap)
:
mkdir -p "$WORK/hwmon" "$WORK/empty" "$WORK/bin" "$WORK/lib" "$WORK/throttle"
printf 'level: 0\n' > "$WORK/fan"
cat > "$WORK/lib/logger" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$FAN_TEST_LOG"
case "${0##*/}" in
  systemctl)
    if [[ $1 == is-active && $2 == thinkpad-fan-hold.service ]]; then
      echo "${TEST_HOLD_STATE:-inactive}"
      exit "${TEST_HOLD_RC:-0}"
    fi
    if [[ ${TEST_THINKFAN_INSTALLED:-yes} == no && $2 == thinkfan.service ]]; then
      case "$1" in
        list-unit-files|cat|status) echo 'Unit thinkfan.service could not be found.' >&2; exit 1 ;;
        start) echo 'Unit thinkfan.service could not be found.' >&2; exit 5 ;;
      esac
    fi
    if [[ $1 == start && -n ${TEST_SYSTEMCTL_START_RC:-} ]]; then
      exit "$TEST_SYSTEMCTL_START_RC"
    fi
    exit "${TEST_SYSTEMCTL_RC:-0}" ;;
  systemd-run) exit "${TEST_SYSTEMD_RUN_RC:-0}" ;;
  pkexec) exit "${TEST_PKEXEC_RC:-0}" ;;
  sudo)
    [[ ${1:-} == probe ]] && exit "${TEST_SUDO_RC:-0}"
    [[ ${TEST_SUDO_RC:-0} -eq 0 ]] || exit "$TEST_SUDO_RC"
    "$@"
    exit $? ;;
  rm)
    printf 'fan-before-rm %s\n' "$(cat "$FAN_TEST_FAN")" >> "$FAN_TEST_LOG"
    exit "${TEST_RM_RC:-0}" ;;
  kpackagetool6) exit "${TEST_KPACKAGE_RC:-0}" ;;
esac
STUB
for cmd in systemctl systemd-run pkexec sudo rm kpackagetool6; do cp "$WORK/lib/logger" "$WORK/bin/$cmd"; chmod +x "$WORK/bin/$cmd"; done
cat > "$WORK/hold" <<'STUB'
#!/bin/bash
printf 'hold %s\n' "$*" >> "$FAN_TEST_LOG"
STUB
chmod +x "$WORK/hold"
: > "$WORK/log"

box() {
  "$BWRAP" --unshare-net --dev-bind / / --bind "$WORK/fan" /proc/acpi/ibm/fan \
    --bind "$WORK/hwmon" /sys/class/hwmon \
    --bind "$WORK/throttle" /sys/devices/system/cpu/cpu0/thermal_throttle \
    --bind "$WORK/bin/systemctl" /usr/bin/systemctl \
    --bind "$WORK/bin/systemd-run" /usr/bin/systemd-run \
    --bind "$WORK/bin/pkexec" /usr/bin/pkexec \
    --bind "$WORK/hold" /usr/local/bin/thinkpad-fan-hold \
    --bind "$WORK/bin/sudo" /usr/bin/sudo \
    --bind "$WORK/bin/rm" /usr/bin/rm \
    --bind "$WORK/bin/kpackagetool6" /usr/bin/kpackagetool6 \
    --setenv FAN_TEST_LOG "$WORK/log" --setenv FAN_TEST_FAN "$WORK/fan" "$@"
}
reset_case() { printf 'level: 0\n' > "$WORK/fan"; : > "$WORK/log"; rm -rf "$WORK/hwmon"/*; }
FAILURES=0
report() { local n=$1 label=$2; shift 2; if "$@"; then printf 'PASS F%s %s\n' "$n" "$label"; else printf 'FAIL F%s %s: ожидался заявленный результат\n' "$n" "$label"; FAILURES=$((FAILURES + 1)); fi; }

# Prove all protected absolute paths resolve to our stubs, not host commands.
reset_case
# shellcheck disable=SC2016
if box /bin/bash -c '[[ $(id -u) -ne 0 ]] || exit 8; echo "level auto" > /proc/acpi/ibm/fan; systemctl probe; systemd-run probe; pkexec probe; /usr/bin/sudo probe; /usr/bin/rm probe; /usr/bin/kpackagetool6 probe; /usr/local/bin/thinkpad-fan-hold probe' >/dev/null 2>&1 && [[ $(wc -l < "$WORK/log") -eq 8 ]] && grep -q '^level auto$' "$WORK/fan"; then
  :
else
  fail_setup "подмена абсолютных команд не сработала"
fi

# F1: absent coretemp must be reported and must not keep a low level pinned.
reset_case
box /usr/bin/timeout 0.15 /usr/bin/env TEST_THINKFAN_INSTALLED=yes /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/out" 2>&1; f1rc=$?
# shellcheck disable=SC2329
check_f1_recovery() { local rc=$1; [[ $rc -ne 0 && $rc -ne 124 ]] && [[ -s "$WORK/out" ]] && grep -q 'level auto' "$WORK/fan" && grep -q '^systemctl start thinkfan.service$' "$WORK/log"; }
report 1 'нет coretemp: hold сообщает об отказе и возвращает автоматику thinkfan' check_f1_recovery "$f1rc"
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 40000 > "$WORK/hwmon/hwmon0/temp1_input"; chmod 000 "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/timeout 0.15 /usr/bin/env TEST_THINKFAN_INSTALLED=yes /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/out" 2>&1; f1read=$?
chmod 644 "$WORK/hwmon/hwmon0/temp1_input"
report 1 'нечитаемый до старта датчик возвращает автоматику thinkfan' check_f1_recovery "$f1read"
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 40000 > "$WORK/hwmon/hwmon0/temp1_input"; chmod 644 "$WORK/hwmon/hwmon0/temp1_input"
# shellcheck disable=SC2016
box /usr/bin/timeout 0.7 /bin/bash -c '(sleep 0.10; chmod 000 "$1") & export THINKPAD_FAN_INTERVAL=0.20 TEST_THINKFAN_INSTALLED=yes; exec /bin/bash "$2" 0' _ "$WORK/hwmon/hwmon0/temp1_input" "$ROOT/helpers/thinkpad-fan-hold" >"$WORK/out" 2>&1; f1after=$?
chmod 644 "$WORK/hwmon/hwmon0/temp1_input"
report 1 'датчик стал нечитаемым после старта: hold возвращает автоматику thinkfan' check_f1_recovery "$f1after"
reset_case
box /usr/bin/timeout 0.15 /usr/bin/env THINKPAD_FAN_TCRIT=0 THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; f1pass=$?
report 1 'явно отключенная защита сохраняет удержание' test "$f1pass" -eq 124

# F2: strict threshold in millidegrees; 90.000 is below/equal, 90.500 exceeds.
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 90000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/timeout 0.12 /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; r900=$?
report 2 '90000 м°C сохраняет удержание' test "$r900" -eq 124 -a "$(awk '/^level:/{print $2}' "$WORK/fan")" = 0
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 90500 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/timeout 0.20 /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; r905=$?
report 2 '90500 м°C возвращает автоматику' test "$r905" -eq 0 -a "$(awk '/^level:/{print $2}' "$WORK/fan")" = auto

# F3: exercise helper write failure, hold launch failure, and success.
reset_case
chmod 444 "$WORK/fan"
box /usr/bin/env TEST_SYSTEMD_RUN_RC=0 /bin/bash "$ROOT/helpers/thinkpad-fan-set" 3 >/dev/null 2>&1; rw=$?
chmod 644 "$WORK/fan"
report 3 'ошибка записи возвращает ненулевой код' test "$rw" -ne 0
reset_case
box /usr/bin/env TEST_SYSTEMD_RUN_RC=1 /bin/bash "$ROOT/helpers/thinkpad-fan-set" 3 >/dev/null 2>&1; rs=$?
report 3 'ошибка запуска hold возвращает ненулевой код' test "$rs" -ne 0
reset_case
box /bin/bash "$ROOT/helpers/thinkpad-fan-set" 3 >/dev/null 2>&1; rok=$?
report 3 'успешное переключение запускает hold' test "$rok" -eq 0 -a "$(grep -c '^systemd-run ' "$WORK/log")" -eq 1

# F3 QML reports switch errors and stays quiet after success.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
try { assert.equal(c.switchError(126,''),'Fan level switch failed'); assert.equal(c.switchError(127,''),'Fan level switch failed'); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 3 'отказ переключения дает понятное сообщение в виджете' test "$?" -eq 0
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
try { assert.equal(c.switchError(0,''),''); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 3 'успешное переключение не показывает ошибку' test "$?" -eq 0

# F4 QML state mapping and status parsing.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
const f=c;
try { assert.equal(f.mode('3',false,'active'),'manual'); assert.equal(f.mode('3',false,'inactive'),'level-unheld'); assert.equal(f.mode('3',false,'unknown'),'unknown'); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 4 'одинаковый уровень различает работающий и остановленный hold' test "$?" -eq 0
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
process.exit(c.mode('auto',false,'unknown') === 'automatic' ? 0 : 1);
NODE
report 4 'автоматический уровень по-прежнему показывает автоматический режим' test "$?" -eq 0
box /usr/bin/env TEST_HOLD_STATE=active TEST_HOLD_RC=0 /bin/bash "$ROOT/helpers/thinkpad-fan-status" >"$WORK/hold-active.out" 2>/dev/null
box /usr/bin/env TEST_HOLD_STATE=inactive TEST_HOLD_RC=3 /bin/bash "$ROOT/helpers/thinkpad-fan-status" >"$WORK/hold-inactive.out" 2>/dev/null
box /usr/bin/env TEST_HOLD_STATE=unknown TEST_HOLD_RC=4 /bin/bash "$ROOT/helpers/thinkpad-fan-status" >"$WORK/hold-unknown.out" 2>/dev/null
# shellcheck disable=SC2329
check_f4_status() {
  [[ $(awk -F'|' '{print $5}' "$WORK/hold-active.out") == active ]] &&
    [[ $(awk -F'|' '{print $5}' "$WORK/hold-inactive.out") == inactive ]] &&
    [[ $(awk -F'|' '{print $5}' "$WORK/hold-unknown.out") == unknown ]] &&
    [[ $(grep -c '^systemctl is-active thinkpad-fan-hold.service$' "$WORK/log") -eq 3 ]]
}
report 4 'status helper exports active, inactive, and unknown hold state' check_f4_status

# F5 uninstall after selecting level 0 must restore auto before deleting parts.
reset_case
box /bin/bash "$ROOT/helpers/thinkpad-fan-set" 0 >/dev/null 2>&1
box /usr/bin/env PATH=/usr/bin:/bin bash "$ROOT/install.sh" --uninstall >"$WORK/uninstall.out" 2>&1; ru=$?
# shellcheck disable=SC2329
check_f5_restore() { [[ $ru -eq 0 ]] && grep -q '^fan-before-rm level auto$' "$WORK/log"; }
report 5 'uninstall возвращает auto до удаления компонентов' check_f5_restore
# shellcheck disable=SC2329
check_f5_stubs() { grep -q '^sudo rm ' "$WORK/log" && grep -q '^rm -f ' "$WORK/log" && grep -q '^systemctl stop thinkpad-fan-hold' "$WORK/log"; }
report 5 'uninstall использует только заглушки удаления и служб' check_f5_stubs
reset_case
box /bin/bash "$ROOT/helpers/thinkpad-fan-set" 0 >/dev/null 2>&1
box /usr/bin/env TEST_SYSTEMCTL_START_RC=1 PATH=/usr/bin:/bin bash "$ROOT/install.sh" --uninstall >"$WORK/uninstall-fail.out" 2>&1; rufail=$?
# shellcheck disable=SC2329
check_f5_failure() { [[ $rufail -ne 0 ]] && grep -Eqi 'auto|automatic|fan|restore|return' "$WORK/uninstall-fail.out"; }
report 5 'uninstall сообщает отказ запуска автоматического управления' check_f5_failure

# F6 samples 10,11,11: unknown baseline, one event, no event; never current-state label.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c); const f=c;
try { let baseline=null; let a=f.throttle(baseline,10); assert.equal(a,null); baseline=f.nextThrottleBaseline(10); let b=f.throttle(baseline,11); assert.equal(b,1); baseline=f.nextThrottleBaseline(11); let d=f.throttle(baseline,11); assert.equal(d,0); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 6 'счётчик 10, 11, 11 описывает события за интервал' test "$?" -eq 0
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
process.exit(c.throttle(11,11) === 0 ? 0 : 1);
NODE
report 6 'неизменившийся счётчик не добавляет событий' test "$?" -eq 0

# F7 unavailable fields stay distinct from real zeros and reset the count baseline.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c); const f=c;
try { assert.equal(f.sensorValue(undefined),null); assert.equal(f.sensorValue(0),0); assert.equal(f.throttle(10,null),null); assert.equal(f.nextThrottleBaseline(null),null); assert.equal(f.throttle(null,0),null); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 7 'недоступность датчиков и счётчика отличается от нулей' test "$?" -eq 0
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
process.exit(c.sensorValue(0) === 0 ? 0 : 1);
NODE
report 7 'реальное нулевое измерение сохраняется как ноль' test "$?" -eq 0
reset_case
box /bin/bash "$ROOT/helpers/thinkpad-fan-status" >"$WORK/status.out" 2>/dev/null
status_count=$(awk -F'|' '{print $4}' "$WORK/status.out")
report 7 'ошибка чтения счётчика отражается как unavailable' test "$status_count" = unavailable

# F8 overheating: auto write failure and thinkfan start failure must be detected;
# firmware auto without thinkfan is valid.
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box_full_fan() {
  "$BWRAP" --unshare-net --dev-bind / / --bind /dev/full /proc/acpi/ibm/fan \
    --bind "$WORK/hwmon" /sys/class/hwmon \
    --bind "$WORK/throttle" /sys/devices/system/cpu/cpu0/thermal_throttle \
    --bind "$WORK/bin/systemctl" /usr/bin/systemctl \
    --bind "$WORK/bin/systemd-run" /usr/bin/systemd-run \
    --bind "$WORK/bin/pkexec" /usr/bin/pkexec \
    --bind "$WORK/hold" /usr/local/bin/thinkpad-fan-hold \
    --bind "$WORK/bin/sudo" /usr/bin/sudo \
    --bind "$WORK/bin/rm" /usr/bin/rm \
    --bind "$WORK/bin/kpackagetool6" /usr/bin/kpackagetool6 \
    --setenv FAN_TEST_LOG "$WORK/log" --setenv FAN_TEST_FAN "$WORK/fan" "$@"
}
box_full_fan /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/f8write" 2>&1; rfw=$?
# shellcheck disable=SC2329
check_f8_write() { [[ $rfw -ne 0 ]] && grep -Eqi 'auto|automatic|fan|temperature|space left' "$WORK/f8write"; }
report 8 'отказ записи auto обнаруживается' check_f8_write
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 TEST_THINKFAN_INSTALLED=yes TEST_SYSTEMCTL_START_RC=1 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/f8service" 2>&1; rfs=$?
# shellcheck disable=SC2329
check_f8_service() { [[ $rfs -ne 0 ]] && grep -q '^systemctl start thinkfan.service$' "$WORK/log"; }
report 8 'отказ запуска thinkfan обнаруживается' check_f8_service
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 TEST_THINKFAN_INSTALLED=no /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; rfa=$?
# shellcheck disable=SC2329
check_f8_firmware() { [[ $rfa -eq 0 ]] && grep -q 'level auto' "$WORK/fan"; }
report 8 'автоматика прошивки без thinkfan допустима' check_f8_firmware

[[ $FAILURES -gt 0 ]] && exit 1
exit 0
