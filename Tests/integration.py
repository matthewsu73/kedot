"""Native server + extension HTTP integration. No user data or real Chrome history is touched."""
import json, os, pathlib, select, shutil, socket, subprocess, sys, tempfile, time, urllib.request, urllib.error
ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'.build/debug/BiliWidget'
NODE = shutil.which('node')
if not NODE: raise SystemExit('Node.js 18+ required for extension integration tests')

def available_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); return s.getsockname()[1]

def start(directory,port):
    env = dict(os.environ,BILI_TRACKER_DATA_DIR=str(directory),BILI_TRACKER_PORT=str(port))
    proc = subprocess.Popen([str(BINARY),'--headless'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if not select.select([proc.stdout],[],[],15)[0]:
        proc.terminate(); raise AssertionError('native server did not become ready')
    assert proc.stdout.readline().startswith('READY'), proc.stderr.read()
    return proc

def post(port,token,path,body,headers=None):
    h={'Content-Type':'application/json','Authorization':'Bearer '+token};h.update(headers or {})
    req=urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=body if isinstance(body,bytes) else json.dumps(body).encode(),headers=h)
    try:
        with urllib.request.urlopen(req,timeout=5) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as error:return error.code,json.load(error)

with tempfile.TemporaryDirectory() as temp:
    directory=pathlib.Path(temp);port=available_port();proc=start(directory,port)
    try:
        token=(directory/'token.txt').read_text().strip()
        assert post(port,token,'/health',{})[0]==200
        # Verify the actual listening endpoint, rather than inferring it from source.
        listeners=subprocess.check_output(['/usr/sbin/lsof','-nP','-a','-p',str(proc.pid),'-iTCP','-sTCP:LISTEN'],text=True)
        assert f'127.0.0.1:{port}' in listeners and '*:' not in listeners
        for wrong in ['wrong','']:
            assert post(port,wrong,'/health',{})[0]==401
        assert post(port,token,'/health',{}, {'Origin':'https://evil.example'})[0]==403
        assert post(port,token,'/health',{}, {'Host':'evil.example'})[0]==403
        for body in [b'{bad', b'null', b'{"items":[null]}', b'{"items":null}']:
            assert post(port,token,'/history',body)[0]==400
        url='https://www.bilibili.com/video/BV1234567890?p=2'
        for number in [float('nan'),float('inf'),-1,1000,True,'42']:
            assert post(port,token,'/progress',dict(url=url,seconds=number,duration=100))[0]==400
        env=dict(os.environ,TEST_TARGET=f'http://127.0.0.1:{port}',TEST_TOKEN=token)
        subprocess.run([NODE,str(ROOT/'Tests/test_extension.cjs')],env=env,check=True)
        db=json.loads((directory/'data.json').read_text());assert db['videos'][url]['seconds']==42
        base=url.split('?')[0]
        assert db['courses'][base]['totalParts']==60 and db['courses'][base]['currentPart']==2
        assert post(port,token,'/health',{})[0]==200
        # Duplicate instance / occupied port must fail instead of running another writer.
        other=subprocess.run([str(BINARY),'--headless'],env=dict(os.environ,BILI_TRACKER_DATA_DIR=str(directory),BILI_TRACKER_PORT=str(port)),capture_output=True,text=True,timeout=10)
        assert other.returncode != 0
        occupied=available_port()
        with socket.socket() as blocking:
            blocking.bind(('127.0.0.1',occupied));blocking.listen()
            with tempfile.TemporaryDirectory() as second_dir:
                other=subprocess.run([str(BINARY),'--headless'],env=dict(os.environ,BILI_TRACKER_DATA_DIR=second_dir,BILI_TRACKER_PORT=str(occupied)),capture_output=True,text=True,timeout=10)
                assert other.returncode != 0
        print('PASS: real native HTTP, loopback-only binding, malformed requests, extension worker -> native -> JSON, duplicate instance and port conflict')
    finally:
        proc.terminate();proc.wait(timeout=5)
    proc=start(directory,port)
    try:
        assert (directory/'token.txt').read_text().strip()==token
        assert json.loads((directory/'data.json').read_text())['videos'][url]['seconds']==42
        assert post(port,token,'/health',{})[0]==200
        print('PASS: native process restart preserves token and playback data')
        for seconds in range(43,53):
            assert post(port,token,'/progress',dict(url=url,seconds=seconds,duration=100,deferSave=True))[0]==200
        assert json.loads((directory/'data.json').read_text())['videos'][url]['seconds']==42
        deadline=time.monotonic()+13
        while time.monotonic()<deadline:
            if json.loads((directory/'data.json').read_text())['videos'][url]['seconds']==52:break
            time.sleep(.1)
        else:raise AssertionError('coalesced progress did not reach disk')
        print('PASS: ten live progress requests update without immediate disk writes; scheduled flush persists the latest value')
    finally:proc.terminate();proc.wait(timeout=5)
