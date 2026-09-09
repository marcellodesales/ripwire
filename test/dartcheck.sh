#!/usr/bin/env bash
# dartcheck.sh — Dart grammar + extraction + dependency-resolution gate.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/dartfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for dartcheck.sh"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "dartcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache >"$TMP/map.xml" 2>"$TMP/map.err"
MAP_RC=$?
[ "$MAP_RC" -eq 0 ] && ok "default map exits 0 on the Dart fixture" || no "default map exited $MAP_RC"
[ ! -s "$TMP/map.err" ] && ok "default map keeps stderr clean" || no "default map wrote stderr: $( cat "$TMP/map.err" )"

command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/map.xml" >/dev/null 2>&1 && ok "default map XML is well-formed" || no "default map XML is malformed"; } \
    || ok "default map XML well-formedness skipped (xmllint absent)"

python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
files = {f.get('p'): f for f in root.findall('f')}
assert root.get('root') == 'test/dartfix'
assert len(files) == 10, files.keys()
assert 'packages/config_only/lib/config_only.dart' in files
assert 'packages/support/lib/support.dart' in files
assert '.dart_tool/package_config.json' in files
main = files['lib/main.dart']
by_name = files['lib/src/by_name.dart']
piece = files['lib/src/piece.dart']
def rows(file_node):
    return [(s.get('t'), s.get('n'), s.get('id'), s.get('overloads'), [c.get('n') for c in s.findall('c')]) for s in file_node.findall('s')]
main_rows = {name: (kind, sid, overloads, calls) for kind, name, sid, overloads, calls in rows(main)}
assert main_rows['Greeter'][0] == 'method'
assert main_rows['make'][0] == 'method'
assert set(main_rows['make'][3]) == {'named', 'supportMessage', 'configMessage'}
assert main_rows['FancyText'][0] == 'cls'
assert main_rows['UserId'][0] == 'cls'
assert main_rows['Mode'][0] == 'struct'
assert main_rows['answer'][2] == '2'
assert main_rows['total'][2] == '2'
piece_rows = {name: (kind, sid, overloads, calls) for kind, name, sid, overloads, calls in rows(piece)}
assert piece_rows['named'][0] == 'method'
assert piece_rows['stitch'][3] == ['helper']
by_rows = {name: (kind, sid, overloads, calls) for kind, name, sid, overloads, calls in rows(by_name)}
assert by_rows['NamedPiece'][0] == 'cls'
assert by_rows['build'][3] == ['helper']
print('  PASS Dart definitions, overload rows, package-config file and call edges')
PY
if [ $? -ne 0 ]; then no "default map structure drifted"; fi

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.xml" 2>"$TMP/deps.err"
[ ! -s "$TMP/deps.err" ] && ok "--deps keeps stderr clean" || no "--deps wrote stderr: $( cat "$TMP/deps.err" )"
python3 - "$TMP/deps.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
rows = {f.get('p'): [inc.get('t') for inc in f.findall('inc')] for f in root.findall('f')}
assert root.find('health').get('dep_langs').endswith(',dart')
assert rows['lib/main.dart'] == [
    'src/util.dart',
    'src/fallback.dart',
    'src/io_impl.dart',
    'package:config_only/config_only.dart',
    'package:support_pkg/support.dart',
    'src/util.dart',
    'src/piece.dart',
    'src/by_name.dart',
]
assert rows['lib/src/piece.dart'] == ['../main.dart']
assert rows['lib/src/by_name.dart'] == ['sample.named']
afferent = {f.get('p'): f.get('afferent') for f in root.findall('f')}
assert afferent['packages/config_only/lib/config_only.dart'] == '1'
assert afferent['packages/support/lib/support.dart'] == '1'
assert afferent['lib/src/io_impl.dart'] == '1'
print('  PASS Dart deps expose relative/package/part edges and unresolved part-of library names honestly')
PY
if [ $? -ne 0 ]; then no "--deps structure drifted"; fi

"$BIN" "$FIX" --callees=make --no-cache >"$TMP/callees.xml" 2>"$TMP/callees.err"
[ ! -s "$TMP/callees.err" ] && ok "--callees keeps stderr clean" || no "--callees wrote stderr: $( cat "$TMP/callees.err" )"
python3 - "$TMP/callees.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
assert root.tag == 'callees'
assert root.get('count') == '3'
got = {(s.get('n'), s.get('p')) for s in root.findall('s')}
want = {
    ('named', 'lib/main.dart:19'),
    ('configMessage', 'packages/config_only/lib/config_only.dart:1'),
    ('supportMessage', 'packages/support/lib/support.dart:1'),
}
assert got == want, (got, want)
print('  PASS --callees=make sees same-file and package-resolved Dart targets')
PY
if [ $? -ne 0 ]; then no "--callees output drifted"; fi

REL_OUT="$TMP/rel.xml"
ABS_OUT="$TMP/abs.xml"
"$BIN" "$FIX" --callees=make --no-cache >"$REL_OUT"
"$BIN" "$FIX" --cache="$TMP/cache.bin" >/dev/null 2>&1
"$BIN" "$FIX" --callees=make --cache="$TMP/cache.bin" >"$TMP/warm.xml"
cmp -s "$REL_OUT" "$TMP/warm.xml" && ok "warm == cold on the Dart caller/callee view" || no "warm cache changed the Dart caller/callee view"
"$BIN" "$FIX" >"$TMP/a.xml"
"$BIN" "$FIX" >"$TMP/b.xml"
cmp -s "$TMP/a.xml" "$TMP/b.xml" && ok "default map is deterministic across two warm runs" || no "default map is non-deterministic"
"$BIN" "$ROOT/test/dartfix" --callees=make --no-cache >"$ABS_OUT"
python3 - "$REL_OUT" "$ABS_OUT" <<'PY'
import sys, xml.etree.ElementTree as ET
def shape(path):
    root = ET.parse(path).getroot()
    return root.get('count'), sorted((s.get('n'), s.get('p')) for s in root.findall('s'))
assert shape(sys.argv[1]) == shape(sys.argv[2])
print('  PASS relative and absolute roots resolve Dart callees identically')
PY
if [ $? -ne 0 ]; then no "relative/absolute root parity failed"; fi

PATH="$( cd "$( dirname "$BIN" )" && pwd ):$PATH" "$BIN" "$FIX" --doctor >"$TMP/doctor.xml"
python3 - "$TMP/doctor.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = {c.get('n'): c for c in ET.parse(sys.argv[1]).iter('c')}
assert rows['grammars'].get('loaded') == rows['grammars'].get('expected') == '23'
assert rows['tree-sitter'].get('languages') == '23'
print('  PASS doctor reports all 23 grammars, including Dart')
PY
if [ $? -ne 0 ]; then no "doctor grammar count drifted"; fi

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
FS='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"path":"'"$FIX"'","symbol":"make"}}}'
printf '%s\n%s\n' "$INIT" "$FS" | "$BIN" --mcp >"$TMP/mcp_find.json"
python3 - "$TMP/mcp_find.json" <<'PY'
import json, sys
payload = json.loads(open(sys.argv[1]).read().splitlines()[-1])['result']['content'][0]['text']
data = json.loads(payload)
assert data['symbol']['name'] == 'make'
assert data['symbol']['line'] == 21
assert data['count'] == 3
assert {row['name'] for row in data['calls']} == {'named', 'supportMessage', 'configMessage'}
print(data['symbol']['handle'])
PY >"$TMP/handle.txt"
if [ $? -eq 0 ]; then ok "MCP find_symbol sees the same Dart callees as CLI --callees"; else no "MCP find_symbol drifted"; fi
HANDLE="$( cat "$TMP/handle.txt" 2>/dev/null )"
FB='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fetch_body","arguments":{"path":"'"$FIX"'","handle":"'"$HANDLE"'"}}}'
printf '%s\n%s\n' "$INIT" "$FB" | "$BIN" --mcp >"$TMP/mcp_body.json"
python3 - "$TMP/mcp_body.json" <<'PY'
import json, sys
payload = json.loads(open(sys.argv[1]).read().splitlines()[-1])['result']['content'][0]['text']
data = json.loads(payload)
assert data['name'] == 'make'
assert data['line'] == 21
assert data['body'] == 'factory Greeter.make() => Greeter.named( supportMessage() + configMessage() );'
print('  PASS MCP fetch_body returns the Dart body for the handle find_symbol emitted')
PY
if [ $? -ne 0 ]; then no "MCP fetch_body drifted"; fi

MUT="$TMP/mut"
cp -R "$FIX" "$MUT"
python3 - "$MUT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
main = root / 'lib' / 'main.dart'
main.write_text(main.read_text().replace('configMessage()', 'missingConfigMessage()'))
cfg = root / '.dart_tool' / 'package_config.json'
data = json.loads(cfg.read_text())
for pkg in data['packages']:
    if pkg['name'] == 'config_only':
        pkg['rootUri'] = '../packages/missing/'
cfg.write_text(json.dumps(data, indent=2) + '\n')
PY
"$BIN" "$MUT" --callees=make --no-cache >"$TMP/mut_callees.xml"
"$BIN" "$MUT" --deps --no-cache >"$TMP/mut_deps.xml"
python3 - "$TMP/mut_callees.xml" "$TMP/mut_deps.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
callees = ET.parse(sys.argv[1]).getroot()
deps = ET.parse(sys.argv[2]).getroot()
assert callees.get('count') == '2'
assert {s.get('n') for s in callees.findall('s')} == {'named', 'supportMessage'}
assert all(f.get('p') != 'packages/config_only/lib/config_only.dart' for f in deps.findall('f'))
print('  PASS mutation controls: breaking the call and package_config mapping removes the asserted edge/file')
PY
if [ $? -ne 0 ]; then no "mutation controls failed"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
