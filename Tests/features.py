from pathlib import Path
import os,subprocess,tempfile,uuid,sys
ROOT=Path(__file__).resolve().parents[1]
binary=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'.build/debug/BiliWidget'
output=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else ROOT/'work/feature-previews'
output.mkdir(parents=True,exist_ok=True)
suite='local.biliwidget.featuretest.'+uuid.uuid4().hex
with tempfile.TemporaryDirectory() as directory:
 env=dict(os.environ,BILI_TRACKER_DATA_DIR=directory,BILI_TRACKER_PREFERENCES_SUITE=suite)
 try:
  result=subprocess.run([str(binary),'--feature-checks'],env=env,capture_output=True,text=True,timeout=15)
  print(result.stdout,flush=True);assert result.returncode==0,result.stderr
  for mode,size in [('light','354x430'),('dark','354x430'),('dark','282x310'),('dark','520x620')]:
   png=(output/(mode+'-'+size+'.png')).resolve()
   args=[str(binary),'--preview','--appearance',mode,'--theme','mint','--size',size,'--snapshot',str(png)]
   if size=='520x620':args+=['--manager-snapshot',str((output/'manager.png').resolve())]
   result=subprocess.run(args,env=env,capture_output=True,text=True,timeout=30)
   assert result.returncode==0,(mode,size,result.stderr)
   assert png.stat().st_size>1000
   print('PASS native '+mode+' '+size,flush=True)
 finally:subprocess.run(['/usr/bin/defaults','delete',suite],capture_output=True)
