"""Offline regression checks against the exact upstream source tree.
Run: python westbeauty/test_customization.py ../ximei-remote-upstream-1.4.9
The fixture uses git object contents, never resets the caller's working tree.
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

UPSTREAM=Path(sys.argv.pop(1)).resolve()
BUNDLE=Path(__file__).resolve().parent.parent

class CustomizationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        files=['Cargo.toml','src/lang.rs','src/lang/template.rs','src/lang/cn.rs',
               'src/flutter.rs','src/ui_interface.rs','src/platform/windows.rs',
               'src/core_main.rs','flutter/windows/runner/main.cpp',
               'flutter/windows/runner/Runner.rc']
        self.original={}
        for relative in files:
            data=subprocess.check_output(['git','show','HEAD:'+relative],cwd=UPSTREAM)
            self.original[relative]=data
            p=self.root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        p=self.root/'libs/hbb_common/src/config.rs';p.parent.mkdir(parents=True)
        p.write_bytes(subprocess.check_output(['git','show','HEAD:src/config.rs'],cwd=UPSTREAM/'libs/hbb_common'))
        self.run_patch()
    def tearDown(self): self.temp.cleanup()
    def run_patch(self):
        return subprocess.run([sys.executable,str(BUNDLE/'westbeauty/patch_rustdesk.py'),str(self.root),'--bundle',str(BUNDLE)],capture_output=True,text=True,check=True)
    def read(self,p):return (self.root/p).read_text()
    def test_install_identity_and_service_names(self):
        cfg=self.read('libs/hbb_common/src/config.rs');win=self.read('src/platform/windows.rs')
        self.assertIn('RwLock::new("WestBeautyRemote".to_owned())',cfg)
        self.assertIn('{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1',win)
        install=win.split('pub fn install_me(',1)[1].split('pub fn run_after_install',1)[0]
        self.assertIn('let app_name = crate::get_app_name();',install)
        self.assertNotIn('let app_name = "西美远控"',install)
    def test_server_defaults_and_no_unattended_credentials(self):
        cfg=self.read('libs/hbb_common/src/config.rs')
        self.assertIn('132.232.176.184:21116',cfg)
        self.assertIn('132.232.176.184:21117',cfg)
        self.assertIn('lrfk1XsoC0Swy5f1iJBSjeXpUsywi+h77GZispaimNw=',cfg)
        block=cfg.split('// WEST_BEAUTY_BUILTIN_SERVER_BEGIN',1)[1].split('// WEST_BEAUTY_BUILTIN_SERVER_END',1)[0]
        self.assertNotIn('password',block)
        self.assertNotIn('hide',block)
    def test_visible_brand_and_language(self):
        self.assertIn('"西美远控".to_owned()',self.read('src/ui_interface.rs'))
        self.assertIn('wide_string("西美远控")',self.read('src/flutter.rs'))
        self.assertIn('or_insert_with(|| "zh-cn".to_owned())',self.read('libs/hbb_common/src/config.rs'))
    def test_preserves_translation_keys_and_license(self):
        self.assertEqual((self.root/'src/lang/template.rs').read_bytes(),self.original['src/lang/template.rs'])
        import re
        pat=r'(?m)^\s*\("((?:[^"\\]|\\.)*)",'
        self.assertEqual(re.findall(pat,self.original['src/lang/cn.rs'].decode()),re.findall(pat,self.read('src/lang/cn.rs')))
        before=next(x for x in self.original['Cargo.toml'].decode().splitlines() if x.startswith('LegalCopyright'))
        self.assertIn(before,self.read('Cargo.toml'))
    def test_arguments_and_support_probe(self):
        # Utf8FromUtf16 retains its trailing NUL; preserve upstream trimming.
        self.assertIn('find_last_not_of(" \\n\\r\\t"));',self.read('flutter/windows/runner/main.cpp'))
        self.assertIn('args[0] == "--check-install"',self.read('src/core_main.rs'))
    def test_manifest_matches_package(self):
        manifest=json.loads(self.read('WEST_BEAUTY_CUSTOMIZATION.json'))
        self.assertEqual(manifest['final_exe'],'WestBeautyRemote.exe')
        installer=(BUNDLE/'westbeauty/installer.iss').read_text()
        self.assertIn(manifest['final_exe'],installer)
        self.assertNotIn('Parameters: "--install-service"',installer)
    def test_required_patch_drift_fails_closed(self):
        # A second application is rejected rather than claiming a patch succeeded.
        with self.assertRaises(subprocess.CalledProcessError):self.run_patch()

if __name__=='__main__':unittest.main()
