from pathlib import Path
import re,json
p=Path('scenes/game/game_screen.tscn');s=p.read_text(encoding='utf-8');head=s[:s.index('[node ')];blocks=re.split(r'(?=\[node )',s[s.index('[node '):]);d={}
for b in blocks:
 if not b.strip():continue
 name=re.search(r'name="([^"]+)"',b)[1]
 d[name]=b
# Restore properties truncated by historical read ranges from committed source.
import subprocess
base=subprocess.check_output(['git','-c','safe.directory=C:/Users/chima/development/polkabow','show','HEAD:scenes/game/game_screen.tscn']).decode()
for b in re.split(r'(?=\[node )',base)[1:]:
 name=re.search(r'name="([^"]+)"',b)[1]
 if name not in d:continue
 props=dict(re.findall(r'^([\w/]+) = (.*)$',b,re.M));props.update(dict(re.findall(r'^([\w/]+) = (.*)$',d[name],re.M)))
 d[name]=d[name].splitlines()[0]+'\n'+'\n'.join(k+' = '+v for k,v in props.items())+'\n\n'
for name in ['LogoBalanceSpace','MatchSummary','SummaryBox']:d.pop(name,None)
# Summary was intentionally replaced in the prior user task.
for name in list(d):
 if 'parent="FeedbackLayer/SummaryOverlay/' in d[name]:del d[name]
d['SummaryOverlay']=d['SummaryOverlay'].replace('mouse_filter = 2','mouse_filter = 0')+'script = ExtResource("27_match_end")\n\n'
# Explicit header ordering retains centered logo.
order=['ZoomControls','Brand','SettingsSlot'];remaining=list(d)
def emit(name):
 b=d[name];parent=re.search(r'parent="([^"]+)"',b);path=name if not parent or parent[1]=='.' else parent[1]+'/'+name
 out=b
 children=[n for n in remaining if re.search(r'parent="'+re.escape(path)+r'"',d[n])]
 if name=='HeaderTools':children=order
 for n in children:out+=emit(n)
 return out
root='GameScreen';out=d[root]
for name in remaining:
 if 'parent="."' in d[name].splitlines()[0]:out+=emit(name)
p.write_text(head+out,encoding='utf-8')