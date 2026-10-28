import os,subprocess,tempfile,uuid,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
binary=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'.build/debug/BiliWidget'
output=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else ROOT/'work/theme-previews'
output.mkdir(parents=True,exist_ok=True)
suite='local.biliwidget.test.'+uuid.uuid4().hex
with tempfile.TemporaryDirectory() as directory:
 env=dict(os.environ,BILI_TRACKER_DATA_DIR=directory,BILI_TRACKER_PREFERENCES_SUITE=suite)
 try:
  result=subprocess.run([str(binary),'--theme-checks'],env=env,capture_output=True,text=True,timeout=20)
  print(result.stdout);assert result.returncode==0,result.stderr
  result=subprocess.run([str(binary),'--print-theme'],env=env,capture_output=True,text=True,timeout=10)
  assert result.returncode==0 and result.stdout.strip()=='cream'
  print('PASS: selected theme restored in a separate process')
  for theme in ['mint','ocean','iris','rose','sunset','cream']:
   png=(output/(theme+'.png')).resolve()
   args=[str(binary),'--preview','--theme',theme,'--snapshot',str(png)]
   if theme in ('mint','cream'):args+=['--manager-snapshot',str((output/('manager-'+theme+'.png')).resolve())]
   result=subprocess.run(args,env=env,capture_output=True,text=True,timeout=25)
   assert result.returncode==0,(theme,result.stderr)
   assert png.stat().st_size>1000
   print('PASS: native '+theme+' theme render, topmost/compact/manager smoke checks')
 finally:subprocess.run(['/usr/bin/defaults','delete',suite],capture_output=True)
