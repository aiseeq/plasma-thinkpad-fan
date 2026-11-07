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
mkdir -p "$WORK/hwmon" "$WORK/empty" "$WORK/bin" "$WORK/lib" "$WORK/throttle" "$WORK/units"
printf 'level: 0\n' > "$WORK/fan"
unit_file() { printf '%s/%s' "$WORK/units" "$1"; }
unit_set() { printf '%s\n' "$2" > "$(unit_file "$1")"; }
unit_remove() { [[ ! -e $(unit_file "$1") ]] || mv "$(unit_file "$1")" "$(unit_file "$1").unloaded"; }
# shellcheck disable=SC2329
unit_state() { [[ -f $(unit_file "$1") ]] && cat "$(unit_file "$1")"; }
cat > "$WORK/lib/logger" <<'STUB'
#!/bin/bash
base=${0##*/}
prefix=${FAN_TEST_SUDO_CONTEXT:+sudo-context }
printf '%s%s %s\n' "$prefix" "$base" "$*" >> "$FAN_TEST_LOG"
unit_file() { printf '%s/%s' "$FAN_TEST_UNITS" "$1"; }
# shellcheck disable=SC2329
unit_state() { [[ -f $(unit_file "$1") ]] && cat "$(unit_file "$1")"; }
unit_set() { printf '%s\n' "$2" > "$(unit_file "$1")"; }
unit_remove() { [[ ! -e $(unit_file "$1") ]] || mv "$(unit_file "$1")" "$(unit_file "$1").unloaded"; }
case "$base" in
  systemctl)
    op=${1:-}; unit=${2:-}
    opkey=${op^^}; opkey=${opkey//-/_}
    rcvar=TEST_SYSTEMCTL_${opkey}_RC
    rc=${!rcvar:-}
    if [[ -n $rc ]]; then
      if [[ $op == list-unit-files && -n ${TEST_SYSTEMCTL_LIST_UNIT_FILES_OUTPUT:-} ]]; then
        printf '%s\n' "$TEST_SYSTEMCTL_LIST_UNIT_FILES_OUTPUT" >&2
      fi
      exit "$rc"
    fi
    if [[ $op == stop && -n ${TEST_FAIL_STOP_UNIT:-} && $unit == "$TEST_FAIL_STOP_UNIT" ]]; then
      echo "Failed to stop $unit: Access denied" >&2; exit 1
    fi
    case "$op" in
      show)
        # systemctl show -p LoadState --value <unit>
        unit=${!#}
        if [[ $unit == thinkfan.service ]]; then
          [[ ${TEST_THINKFAN_INSTALLED:-yes} == no ]] && echo not-found || echo loaded
        else
          state=$(unit_state "$unit")
          [[ -n $state && $state != unloaded ]] && echo loaded || echo not-found
        fi
        exit 0 ;;
      list-unit-files)
        if [[ $unit == thinkfan.service && ${TEST_THINKFAN_INSTALLED:-yes} == no ]]; then
          echo 'Unit thinkfan.service could not be found.' >&2; exit 1
        fi
        echo "$unit enabled"; exit 0 ;;
      cat|status)
        if [[ $unit == thinkfan.service && ${TEST_THINKFAN_INSTALLED:-yes} == no ]]; then
          echo 'Unit thinkfan.service could not be found.' >&2; exit 1
        fi
        state=$(unit_state "$unit")
        if [[ $unit == thinkfan.service && ${TEST_THINKFAN_INSTALLED:-yes} == yes && -z $state ]]; then
          state=inactive
        fi
        [[ -n $state && $state != unloaded ]] || { echo "Unit $unit could not be found." >&2; exit 1; }
        echo "$unit - $state"; exit 0 ;;
      is-active)
        state=$(unit_state "$unit")
        case "$state" in
          active) echo active; exit 0 ;;
          failed) echo failed; exit 3 ;;
          inactive) echo inactive; exit 3 ;;
          *) echo inactive; exit 4 ;;
        esac ;;
      stop)
        state=$(unit_state "$unit")
        [[ -n $state && $state != unloaded ]] || { echo "Unit $unit not loaded." >&2; exit 5; }
        mv "$(unit_file "$unit")" "$(unit_file "$unit").unloaded"
        exit 0 ;;
      reset-failed)
        state=$(unit_state "$unit")
        [[ -n $state && $state != unloaded ]] || exit 1
        [[ $state != failed ]] || unit_set "$unit" inactive
        exit 0 ;;
      start)
        if [[ $unit == thinkfan.service && ${TEST_THINKFAN_INSTALLED:-yes} == no ]]; then
          echo 'Unit thinkfan.service could not be found.' >&2; exit 5
        fi
        if [[ -n ${TEST_SYSTEMCTL_START_RC:-} && $TEST_SYSTEMCTL_START_RC -ne 0 ]]; then
          exit "$TEST_SYSTEMCTL_START_RC"
        fi
        unit_set "$unit" active; exit 0 ;;
    esac
    exit "${TEST_SYSTEMCTL_RC:-0}" ;;
  systemd-run)
    rc=${TEST_SYSTEMD_RUN_RC:-0}
    if [[ $rc -eq 0 ]]; then
      for arg in "$@"; do
        if [[ $arg == --unit=* ]]; then
          unit=${arg#--unit=}; [[ $unit == *.service ]] || unit+=.service
          unit_set "$unit" "${TEST_SYSTEMD_RUN_HOLD_STATE:-active}"
        fi
      done
    fi
    exit "$rc" ;;
  pkexec) exit "${TEST_PKEXEC_RC:-0}" ;;
  sudo)
    [[ ${1:-} == probe ]] && exit 0
    if [[ ${1:-} == /usr/local/bin/thinkpad-fan-set && ${TEST_SUDO_SET_RC:-0} -ne 0 ]]; then
      exit "$TEST_SUDO_SET_RC"
    fi
    [[ ${TEST_SUDO_RC:-0} -eq 0 ]] || exit "$TEST_SUDO_RC"
    FAN_TEST_SUDO_CONTEXT=1 "$@"; exit $? ;;
  rm)
    echo rm-observed-fan >> "$FAN_TEST_LOG"
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
    --bind "$ROOT/helpers/thinkpad-fan-set" /usr/local/bin/thinkpad-fan-set \
    --bind "$ROOT/helpers/thinkpad-fan-status" /usr/local/bin/thinkpad-fan-status \
    --bind "$WORK/bin/sudo" /usr/bin/sudo \
    --bind "$WORK/bin/rm" /usr/bin/rm \
    --bind "$WORK/bin/kpackagetool6" /usr/bin/kpackagetool6 \
    --setenv FAN_TEST_LOG "$WORK/log" --setenv FAN_TEST_FAN "$WORK/fan" \
    --setenv FAN_TEST_UNITS "$WORK/units" "$@"
}
reset_case() { printf 'level: 0\n' > "$WORK/fan"; : > "$WORK/log"; rm -rf "$WORK/hwmon"/* "$WORK/units"/*; }
fan_level() {
  local line
  line=$(tail -n 1 "$WORK/fan")
  case "$line" in
    'level: '*) printf '%s\n' "${line#level: }" ;;
    'level '*) printf '%s\n' "${line#level }" ;;
    *) printf 'unknown\n' ;;
  esac
}
echo 'level: 7' > "$WORK/fan"
[[ $(fan_level) == 7 ]] || fail_setup "fan_level не читает формат procfs"
echo 'level 3' > "$WORK/fan"
[[ $(fan_level) == 3 ]] || fail_setup "fan_level не читает обычную строку level"
reset_case
FAILURES=0
report() { local n=$1 label=$2; shift 2; if "$@"; then printf 'PASS F%s %s\n' "$n" "$label"; else printf 'FAIL F%s %s: ожидался заявленный результат\n' "$n" "$label"; FAILURES=$((FAILURES + 1)); fi; }

# Prove all protected absolute paths resolve to our stubs, not host commands.
reset_case
# shellcheck disable=SC2016
if box /bin/bash -c '[[ $(id -u) -ne 0 ]] || exit 8; echo "level auto" > /proc/acpi/ibm/fan; systemctl probe; systemd-run probe; pkexec probe; /usr/bin/sudo probe; /usr/bin/rm probe; /usr/bin/kpackagetool6 probe; /usr/local/bin/thinkpad-fan-hold probe' >/dev/null 2>&1 && [[ $(wc -l < "$WORK/log") -eq 8 ]] && [[ $(fan_level) == auto ]]; then
  :
else
  fail_setup "подмена абсолютных команд не сработала"
fi
box /usr/local/bin/thinkpad-fan-status > "$WORK/status-probe" 2>/dev/null
status_fields=$(awk -F'|' '{print NF}' "$WORK/status-probe")
[[ $status_fields -ge 5 ]] || fail_setup "thinkpad-fan-status не подменён хелпером из дерева"
box /usr/local/bin/thinkpad-fan-set invalid >/dev/null 2>&1; set_probe_rc=$?
[[ $set_probe_rc -eq 2 ]] || fail_setup "thinkpad-fan-set не подменён хелпером из дерева"

# F1: absent coretemp must be reported and must not keep a low level pinned.
reset_case
box /usr/bin/timeout 0.15 /usr/bin/env TEST_THINKFAN_INSTALLED=yes /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/out" 2>&1; f1rc=$?
# shellcheck disable=SC2329
check_f1_recovery() { local rc=$1; [[ $rc -ne 0 && $rc -ne 124 ]] && [[ -s "$WORK/out" ]] && [[ $(fan_level) == auto ]] && grep -q '^systemctl start thinkfan.service$' "$WORK/log"; }
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
report 2 '90000 м°C сохраняет удержание' test "$r900" -eq 124 -a "$(fan_level)" = 0
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 90500 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/timeout 0.20 /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; r905=$?
report 2 '90500 м°C возвращает автоматику' test "$r905" -eq 0 -a "$(fan_level)" = auto

# F3: exercise helper write failure, hold launch failure, and success.
reset_case
chmod 444 "$WORK/fan"
box /usr/bin/env TEST_SYSTEMD_RUN_RC=0 /bin/bash "$ROOT/helpers/thinkpad-fan-set" 3 >"$WORK/set-write.out" 2>&1; rw=$?
chmod 644 "$WORK/fan"
report 3 'ошибка записи возвращает ненулевой код' test "$rw" -ne 0 -a -s "$WORK/set-write.out"
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no TEST_SYSTEMD_RUN_RC=1 /bin/bash "$ROOT/helpers/thinkpad-fan-set" 3 >/dev/null 2>&1; rs=$?
report 3 'ошибка запуска hold возвращает ненулевой код' test "$rs" -ne 0 -a "$(grep -c '^systemd-run ' "$WORK/log")" -eq 1



# shellcheck disable=SC2329
check_f3_nohold() { [[ $nohold_rc -eq 0 && $(unit_state thinkpad-fan-hold.service) == active ]]; }
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no /bin/bash /usr/local/bin/thinkpad-fan-set 3 >/dev/null 2>&1; nohold_rc=$?
report 3 'set 3 starts hold without an old hold or installed thinkfan' check_f3_nohold
# shellcheck disable=SC2329
check_f3_auto() { [[ $auto_rc -eq 0 && $(fan_level) == auto ]]; }
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no /bin/bash /usr/local/bin/thinkpad-fan-set auto >/dev/null 2>&1; auto_rc=$?
report 3 'set auto succeeds without an old hold' check_f3_auto
# shellcheck disable=SC2329
check_f3_replace() {
  local stop_line run_line
  stop_line=$(grep -n '^systemctl stop thinkpad-fan-hold.service$' "$WORK/log" | head -n1 | cut -d: -f1)
  run_line=$(grep -n '^systemd-run ' "$WORK/log" | tail -n1 | cut -d: -f1)
  [[ $replace_rc -eq 0 && $(unit_state thinkpad-fan-hold.service) == active && -n $stop_line && -n $run_line && $stop_line -lt $run_line ]]
}
reset_case
unit_set thinkpad-fan-hold.service active
box /usr/bin/env TEST_THINKFAN_INSTALLED=no /bin/bash /usr/local/bin/thinkpad-fan-set 3 >/dev/null 2>&1; replace_rc=$?
report 3 'set 3 stops an active hold before starting its replacement' check_f3_replace
# shellcheck disable=SC2329
check_f3_run_failure() { [[ $runfail_rc -ne 0 ]] && grep -q '^systemd-run ' "$WORK/log" && [[ $(unit_state thinkpad-fan-hold.service) != active ]]; }
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no TEST_SYSTEMD_RUN_RC=1 /bin/bash /usr/local/bin/thinkpad-fan-set 3 >/dev/null 2>&1; runfail_rc=$?
report 3 'set 3 returns failure when systemd-run refuses the new hold' check_f3_run_failure
# Check that helpers do not detect test filesystems with `stat -f` or proc-fs markers.
# shellcheck disable=SC2329
check_helpers_no_fs_probe() { ! grep -R -Eq 'stat -f|procfs|proc[[:space:]]+filesystem|filesystem[[:space:]]+type|f_type' "$ROOT/helpers"; }
report 3 'helpers do not identify the test filesystem' check_helpers_no_fs_probe

# F3 QML reports switch errors and stays quiet after success.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
try { assert.equal(c.switchError(126,''),'switch-failed'); assert.equal(c.switchError(127,''),'switch-failed'); process.exit(0); } catch(e) { process.exit(1); }
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
reset_case
unit_set thinkpad-fan-hold.service active
box /bin/bash /usr/local/bin/thinkpad-fan-status >"$WORK/hold-active.out" 2>/dev/null
unit_set thinkpad-fan-hold.service inactive
box /bin/bash /usr/local/bin/thinkpad-fan-status >"$WORK/hold-inactive.out" 2>/dev/null
unit_remove thinkpad-fan-hold.service
# A stopped transient hold unit is unloaded: that is the normal "not holding" state, not an unknown one.
box /bin/bash /usr/local/bin/thinkpad-fan-status >"$WORK/hold-unloaded.out" 2>/dev/null
# Unknown is reserved for systemctl failing to answer (no state word, error code).
box /usr/bin/env TEST_SYSTEMCTL_IS_ACTIVE_RC=1 /bin/bash /usr/local/bin/thinkpad-fan-status >"$WORK/hold-unknown.out" 2>/dev/null
# shellcheck disable=SC2329
check_f4_status() {
  [[ $(awk -F'|' '{print $5}' "$WORK/hold-active.out") == active ]] &&
    [[ $(awk -F'|' '{print $5}' "$WORK/hold-inactive.out") == inactive ]] &&
    [[ $(awk -F'|' '{print $5}' "$WORK/hold-unloaded.out") == inactive ]] &&
    [[ $(awk -F'|' '{print $5}' "$WORK/hold-unknown.out") == unknown ]] &&
    [[ $(grep -c '^systemctl is-active thinkpad-fan-hold.service$' "$WORK/log") -eq 4 ]]
}
report 4 'status helper exports active, inactive, and unknown hold state' check_f4_status

# F5 uninstall after selecting level 0 must restore auto before deleting parts.
reset_case
printf 'level 0\n' > "$WORK/fan"; unit_set thinkpad-fan-hold.service active
box /usr/bin/env PATH=/usr/bin:/bin bash "$ROOT/install.sh" --uninstall >"$WORK/uninstall.out" 2>&1; ru=$?
# shellcheck disable=SC2329
check_f5_restore() {
  local set_line rm_line
  set_line=$(grep -n '^sudo /usr/local/bin/thinkpad-fan-set auto$' "$WORK/log" | cut -d: -f1)
  rm_line=$(grep -n '^sudo rm ' "$WORK/log" | head -n1 | cut -d: -f1)
  [[ $ru -eq 0 && -n $set_line && -n $rm_line && $set_line -lt $rm_line ]] &&
    [[ $(fan_level) == auto ]] && ! grep -Eq '^systemctl ' "$WORK/log" &&
    ! grep -Eq '^[[:space:]]*systemctl[[:space:]]|>[[:space:]]*/proc/acpi/ibm/fan' "$ROOT/install.sh"
}
report 5 'uninstall возвращает auto до удаления компонентов' check_f5_restore
# shellcheck disable=SC2329
check_f5_sudo_order() {
  local set_line rm_line
  set_line=$(grep -n '^sudo /usr/local/bin/thinkpad-fan-set auto$' "$WORK/log" | cut -d: -f1)
  rm_line=$(grep -n '^sudo rm ' "$WORK/log" | head -n1 | cut -d: -f1)
  [[ -n $set_line && -n $rm_line && $set_line -lt $rm_line ]]
}
report 5 'sudo set auto precedes the first privileged removal' check_f5_sudo_order
# shellcheck disable=SC2329
check_f5_stubs() { grep -q '^sudo rm ' "$WORK/log" && grep -q '^sudo-context rm -f ' "$WORK/log" && grep -q '^sudo-context systemctl stop thinkpad-fan-hold' "$WORK/log"; }
report 5 'uninstall использует только заглушки удаления и служб' check_f5_stubs
reset_case
printf 'level 0\n' > "$WORK/fan"; unit_set thinkpad-fan-hold.service active
box /usr/bin/env TEST_SUDO_SET_RC=1 PATH=/usr/bin:/bin bash "$ROOT/install.sh" --uninstall >"$WORK/uninstall-fail.out" 2>&1; rufail=$?
# shellcheck disable=SC2329
check_f5_failure() { [[ $rufail -ne 0 ]] && grep -q '^sudo /usr/local/bin/thinkpad-fan-set auto$' "$WORK/log" && grep -Eqi 'auto|automatic|fan|restore|return' "$WORK/uninstall-fail.out" && ! grep -q '^sudo rm ' "$WORK/log"; }
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
# The fan file already reads the held level, so hold never writes before the
# overheat check; it is read-only, so the first write is the "level auto" one.
printf 'level: 0\n' > "$WORK/fan"; chmod 444 "$WORK/fan"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/f8write" 2>&1; rfw=$?
chmod 644 "$WORK/fan"
# shellcheck disable=SC2329
check_f8_write() { [[ $rfw -ne 0 ]] && grep -q 'above' "$WORK/f8write" && grep -Eqi 'restore automatic|automatic fan' "$WORK/f8write"; }
report 8 'отказ записи auto обнаруживается' check_f8_write
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 TEST_THINKFAN_INSTALLED=yes TEST_SYSTEMCTL_START_RC=1 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/f8service" 2>&1; rfs=$?
# shellcheck disable=SC2329
check_f8_service() { [[ $rfs -ne 0 && $(unit_state thinkfan.service) != active ]] && grep -q '^systemctl start thinkfan.service$' "$WORK/log"; }
report 8 'отказ запуска thinkfan обнаруживается' check_f8_service
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 TEST_THINKFAN_INSTALLED=no /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >/dev/null 2>&1; rfa=$?
# shellcheck disable=SC2329
check_f8_firmware() { [[ $rfa -eq 0 ]] && [[ $(fan_level) == auto ]]; }
report 8 'автоматика прошивки без thinkfan допустима' check_f8_firmware

# F3: failed systemd-run must restore automatic control and retain both errors.
reset_case
unit_set thinkfan.service active
box /usr/bin/env TEST_THINKFAN_INSTALLED=yes TEST_SYSTEMD_RUN_RC=1 TEST_SYSTEMCTL_START_RC=1 \
  /bin/bash /usr/local/bin/thinkpad-fan-set 3 >"$WORK/set-run-restore.out" 2>&1; run_restore_rc=$?
# shellcheck disable=SC2329
check_run_restore() {
  [[ $run_restore_rc -ne 0 && $(fan_level) == auto ]] &&
    grep -qi 'failed to start fan hold' "$WORK/set-run-restore.out" &&
    grep -qi 'failed to start thinkfan.service' "$WORK/set-run-restore.out"
}
report 3 'systemd-run failure restores automatic mode and reports restore failure' check_run_restore

# F3: a successful systemd-run can still produce a failed transient unit.
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no TEST_SYSTEMD_RUN_HOLD_STATE=failed \
  /bin/bash /usr/local/bin/thinkpad-fan-set 3 >"$WORK/set-hold-failed.out" 2>&1; hold_failed_rc=$?
# shellcheck disable=SC2329
check_hold_failed() {
  [[ $hold_failed_rc -ne 0 && $(fan_level) == auto ]] &&
    grep -qi 'hold.*failed\|failed.*hold' "$WORK/set-hold-failed.out"
}
report 3 'set detects failed hold after systemd-run and restores auto' check_hold_failed

# F5: uninstall must stop before removal if the set helper is not executable.
printf 'not executable\n' > "$WORK/nonexec-set"
chmod 644 "$WORK/nonexec-set"
box_without_set() {
  "$BWRAP" --unshare-net --dev-bind / / --bind "$WORK/fan" /proc/acpi/ibm/fan \
    --bind "$WORK/bin/systemctl" /usr/bin/systemctl \
    --bind "$WORK/bin/pkexec" /usr/bin/pkexec \
    --bind "$WORK/bin/sudo" /usr/bin/sudo \
    --bind "$WORK/bin/rm" /usr/bin/rm \
    --bind "$WORK/bin/kpackagetool6" /usr/bin/kpackagetool6 \
    --ro-bind "$WORK/nonexec-set" /usr/local/bin/thinkpad-fan-set \
    --setenv FAN_TEST_LOG "$WORK/log" --setenv FAN_TEST_FAN "$WORK/fan" \
    --setenv FAN_TEST_UNITS "$WORK/units" "$@"
}
reset_case
box_without_set /usr/bin/env PATH=/usr/bin:/bin bash "$ROOT/install.sh" --uninstall >"$WORK/uninstall-no-set.out" 2>&1; uninstall_no_set_rc=$?
# shellcheck disable=SC2329
check_uninstall_no_set() {
  [[ $uninstall_no_set_rc -ne 0 ]] &&
    grep -q 'sudo systemctl stop thinkpad-fan-hold.service' "$WORK/uninstall-no-set.out" &&
    grep -q 'echo level auto | sudo tee /proc/acpi/ibm/fan' "$WORK/uninstall-no-set.out" &&
    ! grep -q '^sudo rm ' "$WORK/log" && ! grep -q '^kpackagetool6 ' "$WORK/log"
}
report 5 'uninstall without executable set helper reports manual recovery and removes nothing' check_uninstall_no_set

# F8 and set auto must distinguish a missing optional unit from systemd failure.
reset_case
box /usr/bin/env TEST_SYSTEMCTL_SHOW_RC=1 /bin/bash /usr/local/bin/thinkpad-fan-set auto >"$WORK/set-list-error.out" 2>&1; set_list_error_rc=$?
# shellcheck disable=SC2329
check_set_list_error() {
  [[ $set_list_error_rc -ne 0 ]] && grep -Eqi '(query|check|list).*thinkfan|thinkfan.*(query|check|list)' "$WORK/set-list-error.out"
}
report 8 'set auto reports a failed systemd query for thinkfan' check_set_list_error
reset_case
mkdir -p "$WORK/hwmon/hwmon0"; echo coretemp > "$WORK/hwmon/hwmon0/name"; echo 91000 > "$WORK/hwmon/hwmon0/temp1_input"
box /usr/bin/env THINKPAD_FAN_INTERVAL=0.02 TEST_SYSTEMCTL_SHOW_RC=1 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/hold-list-error.out" 2>&1; hold_list_error_rc=$?
# shellcheck disable=SC2329
check_hold_list_error() {
  [[ $hold_list_error_rc -ne 0 ]] && grep -Eqi '(query|check|list).*thinkfan|thinkfan.*(query|check|list)' "$WORK/hold-list-error.out"
}
report 8 'hold reports a failed systemd query for thinkfan during recovery' check_hold_list_error

# F8: a thinkfan unit that is not found is told by LoadState, whatever the language of systemctl messages.
reset_case
box /usr/bin/env TEST_THINKFAN_INSTALLED=no LANG=de_DE.UTF-8 /bin/bash /usr/local/bin/thinkpad-fan-set auto >"$WORK/set-noth.out" 2>&1; set_noth_rc=$?
# shellcheck disable=SC2329
check_set_noth() { [[ $set_noth_rc -eq 0 && $(fan_level) == auto ]] && grep -q '^systemctl show -p LoadState --value thinkfan.service$' "$WORK/log"; }
report 8 'set auto without thinkfan is decided by LoadState' check_set_noth

# F1/F8: hold that cannot write its level gives control back instead of vanishing.
reset_case
printf 'level: 3\n' > "$WORK/fan"; chmod 444 "$WORK/fan"
box /usr/bin/env THINKPAD_FAN_TCRIT=0 THINKPAD_FAN_INTERVAL=0.02 /bin/bash "$ROOT/helpers/thinkpad-fan-hold" 0 >"$WORK/hold-wfail.out" 2>&1; hold_wfail_rc=$?
chmod 644 "$WORK/fan"
# shellcheck disable=SC2329
check_hold_wfail() { [[ $hold_wfail_rc -ne 0 && $hold_wfail_rc -ne 124 ]] && grep -q 'failed to write fan level' "$WORK/hold-wfail.out" && grep -q '^systemctl start thinkfan.service$' "$WORK/log"; }
report 1 'hold write failure restores automatic control' check_hold_wfail

# F3: failing to stop the old hold after thinkfan was stopped gives thinkfan back.
reset_case
unit_set thinkfan.service active; unit_set thinkpad-fan-hold.service active
box /usr/bin/env TEST_FAIL_STOP_UNIT=thinkpad-fan-hold.service /bin/bash /usr/local/bin/thinkpad-fan-set 3 >"$WORK/set-hfail.out" 2>&1; set_hfail_rc=$?
# shellcheck disable=SC2329
check_set_hfail() { [[ $set_hfail_rc -ne 0 ]] && grep -q '^systemctl stop thinkfan.service$' "$WORK/log" && grep -q '^systemctl start thinkfan.service$' "$WORK/log" && ! grep -q '^systemd-run ' "$WORK/log"; }
report 3 'set restarts thinkfan when the old hold cannot be stopped' check_set_hfail

# F7: failed and incomplete polls clear old readings and the counter baseline.
node - "$ROOT/package/contents/code/fanstate.js" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
try {
  const healthy=c.applyStatus(10,'3|inactive|2200|11|active',0);
  assert.equal(healthy.freqMhz,2200); assert.equal(healthy.throttleDelta,1); assert.equal(healthy.throttleBaseline,11);
  const failed=c.applyStatus(healthy.throttleBaseline,'',1);
  assert.equal(failed.freqMhz,null); assert.equal(failed.throttleCount,null); assert.equal(failed.throttleBaseline,null);
  const afterFailure=c.applyStatus(failed.throttleBaseline,'3|inactive|2200|20|active',0);
  assert.equal(afterFailure.throttleDelta,null);
  const incomplete=c.applyStatus(afterFailure.throttleBaseline,'3|inactive|2200|21',0);
  assert.equal(incomplete.freqMhz,null); assert.equal(incomplete.throttleBaseline,null);
  process.exit(0);
} catch(e) { process.exit(1); }
NODE
report 7 'failed and incomplete status polls clear values and throttle baseline' test "$?" -eq 0

# F3: switch error codes stay separate from translatable QML literals.
node - "$ROOT/package/contents/code/fanstate.js" "$ROOT/package/contents/ui/main.qml" <<'NODE'
const fs=require('fs'),vm=require('vm'),assert=require('assert'); const c={}; vm.createContext(c); vm.runInContext(fs.readFileSync(process.argv[2],'utf8').split(String.fromCharCode(10)).slice(1).join(String.fromCharCode(10)),c);
const qml=fs.readFileSync(process.argv[3],'utf8');
try { assert.equal(c.switchError(127,''),'switch-failed'); assert.equal(c.switchError(0,''),''); assert(qml.includes('i18n("Fan level switch failed")')); assert(!qml.includes('i18n(FanState.switchError')); process.exit(0); } catch(e) { process.exit(1); }
NODE
report 3 'switch failure code maps to a literal translatable QML message' test "$?" -eq 0

[[ $FAILURES -gt 0 ]] && exit 1
exit 0
