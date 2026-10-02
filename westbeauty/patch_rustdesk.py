#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from pathlib import Path
import re, shutil, json, sys

DISPLAY="西美远控"
COMPANY="West Beauty Group"
INTERNAL="WestBeautyRemote"
SERVER="132.232.176.184"
ID_SERVER=SERVER+":21116"
RELAY_SERVER=SERVER+":21117"
KEY="lrfk1XsoC0Swy5f1iJBSjeXpUsywi+h77GZispaimNw="

root=Path(sys.argv[1]).resolve()
bundle=Path(sys.argv[3]).resolve() if len(sys.argv)>3 and sys.argv[2]=="--bundle" else Path.cwd()
brand=bundle/"branding"

def rd(p): return p.read_text(encoding="utf-8")
def wr(p,s): p.write_text(s,encoding="utf-8",newline="")
def rep(p,a,b,required=False,count=-1):
    if not p.exists():
        if required: raise RuntimeError(f"Missing {p}")
        return 0
    s=rd(p); n=s.count(a)
    if required and n==0: raise RuntimeError(f"Patch point not found in {p}: {a}")
    if n:
        wr(p,s.replace(a,b,count if count>=0 else n))
    return n

cfg=root/"libs/hbb_common/src/config.rs"
if not cfg.exists(): raise RuntimeError("hbb_common config.rs not found")
s=rd(cfg)
s,n=re.subn(r'(?m)^pub const RENDEZVOUS_SERVERS\s*:\s*[^=]+?=\s*&\[[^\n]*\];',
            f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{SERVER}"];',s)
if n==0: raise RuntimeError("RENDEZVOUS_SERVERS patch failed")
s,n2=re.subn(r'(?m)^pub const RS_PUB_KEY\s*:\s*&str\s*=\s*"[^"]*";',
             f'pub const RS_PUB_KEY: &str = "{KEY}";',s)
if n2==0: raise RuntimeError("RS_PUB_KEY patch failed")
s=s.replace('pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());',
            f'pub static ref APP_NAME: RwLock<String> = RwLock::new("{INTERNAL}".to_owned());')
anchor='let mut config = Config::load_::<Config2>("2");'
if "WEST_BEAUTY_BUILTIN_SERVER_BEGIN" not in s:
    if anchor not in s: raise RuntimeError("Config2::load anchor not found")
    block=anchor+f'''
        // WEST_BEAUTY_BUILTIN_SERVER_BEGIN
        config.rendezvous_server = "{ID_SERVER}".to_owned();
        config.options.insert("custom-rendezvous-server".to_owned(), "{SERVER}".to_owned());
        config.options.insert("relay-server".to_owned(), "{RELAY_SERVER}".to_owned());
        config.options.insert("key".to_owned(), "{KEY}".to_owned());
        // WEST_BEAUTY_BUILTIN_SERVER_END'''
    s=s.replace(anchor,block,1)
wr(cfg,s)

# Visible branding while retaining ASCII internal service/app identity.
p=root/"src/lang.rs"
if p.exists():
    rep(p,'let app_name = crate::get_app_name();',f'let app_name = "{DISPLAY}".to_owned();')
p=root/"src/flutter.rs"
if p.exists():
    rep(p,'let name = crate::platform::wide_string(&crate::get_app_name());',
        f'let name = crate::platform::wide_string("{DISPLAY}");')
p=root/"src/ui_interface.rs"
if p.exists():
    s=rd(p)
    s,n=re.subn(r'(pub fn get_app_name\(\) -> String \{\s*)crate::get_app_name\(\)(\s*\})',
                lambda m:m.group(1)+f'"{DISPLAY}".to_owned()'+m.group(2),s,count=1,flags=re.S)
    if n: wr(p,s)
p=root/"flutter/windows/runner/main.cpp"
if p.exists():
    rep(p,'std::wstring app_name = L"RustDesk";',f'std::wstring app_name = L"{DISPLAY}";')

# Windows resource strings.
for p in [root/"flutter/windows/runner/Runner.rc",root/"flutter/windows/runner/runner.rc"]:
    if p.exists():
        s=rd(p).replace('"RustDesk Remote Desktop"',f'"{DISPLAY}"').replace('"RustDesk"',f'"{DISPLAY}"')
        s=s.replace('"Purslane Tech Pte. Ltd."',f'"{COMPANY}"').replace('"Purslane Ltd."',f'"{COMPANY}"')
        wr(p,s)

# Cargo Windows version resource metadata.
p=root/"Cargo.toml"
if p.exists():
    s=rd(p)
    s=re.sub(r'(?m)^ProductName\s*=\s*"[^"]*"',f'ProductName = "{DISPLAY}"',s)
    s=re.sub(r'(?m)^FileDescription\s*=\s*"[^"]*"',f'FileDescription = "{DISPLAY}"',s)
    wr(p,s)

# Translation values only: replace visible RustDesk text, keep keys intact.
langdir=root/"src/lang"
if langdir.exists():
    vr=re.compile(r'(\(\s*"(?:[^"\\]|\\.)*"\s*,\s*")((?:[^"\\]|\\.)*)("\s*\))')
    for p in langdir.glob("*.rs"):
        if p.name == "template.rs": continue
        old=rd(p)
        new=vr.sub(lambda m:m.group(1)+m.group(2).replace("RustDesk",DISPLAY)+m.group(3),old)
        if new!=old: wr(p,new)

# Inno Setup and Rust must agree on the installation identity. Do not change
# install_me's local identity: it is also used in executable/service paths.
p=root/"src/platform/windows.rs"
rep(p, 'const IS1: &str = "{54E86BC2-6C85-41F3-A9EB-1A94AC9B1F93}_is1";',
       'const IS1: &str = "{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1";', required=True)

# The upstream argument trim removed the final non-whitespace character.
p=root/"flutter/windows/runner/main.cpp"
rep(p, 'argument.erase(argument.find_last_not_of(" \\n\\r\\t"));',
       'argument.erase(argument.find_last_not_of(" \\n\\r\\t") + 1);', required=True)

# Brand the first-run UI in Chinese, while preserving a saved language choice.
p=root/"libs/hbb_common/src/config.rs"
rep(p, '        Config::load_::<LocalConfig>("_local")',
       '        let mut config = Config::load_::<LocalConfig>("_local");\n        config.options.entry("lang".to_owned()).or_insert_with(|| "zh-cn".to_owned());\n        config', required=True)

# Read-only support command, used to verify installed-state recognition in CI.
p=root/"src/core_main.rs"
rep(p, '        if args[0] == "--version" {',
       '        if args[0] == "--check-install" {\n            println!("{}", crate::platform::is_installed());\n            return None;\n        }\n        if args[0] == "--version" {', required=True)

# Vendor strings in installer/UI sources.
for rel in ["flutter/lib/desktop/pages/install_page.dart",
            "src/platform/windows/installer_shell.rs",
            "src/platform/windows/installer_handoff.rs"]:
    p=root/rel
    if p.exists():
        s=rd(p).replace("Purslane Tech Pte. Ltd.",COMPANY).replace("Purslane Ltd.",COMPANY)
        wr(p,s)

# Icons.
for rel in ["res/icon.png","flutter/assets/icon.png","flutter/assets/logo.png"]:
    p=root/rel
    if p.exists() and (brand/"app.png").exists(): shutil.copy2(brand/"app.png",p)
for rel in ["res/icon.ico","flutter/assets/icon.ico","flutter/assets/logo.ico",
            "flutter/windows/runner/resources/app_icon.ico"]:
    p=root/rel
    if p.exists() and (brand/"app.ico").exists(): shutil.copy2(brand/"app.ico",p)
for rel,name in {
    "res/16x16.png":"icon-16.png","res/32x32.png":"icon-32.png",
    "res/48x48.png":"icon-48.png","res/64x64.png":"icon-64.png",
    "res/128x128.png":"icon-128.png","res/128x128@2x.png":"icon-256.png",
    "res/256x256.png":"icon-256.png","res/512x512.png":"icon-512.png"}.items():
    p=root/rel; q=brand/name
    if p.exists() and q.exists(): shutil.copy2(q,p)

manifest={
 "base":"RustDesk 1.4.9","company":COMPANY,"visible_name":DISPLAY,"internal_name":INTERNAL,
 "id_server":ID_SERVER,"relay_server":RELAY_SERVER,"server_public_key":KEY,
 "final_exe":"WestBeautyRemote.exe","installer_version":"2.1.0-rc1"}
(root/"WEST_BEAUTY_CUSTOMIZATION.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
(root/"WEST_BEAUTY_PATCH_LOG.txt").write_text("West Beauty customization applied\n"+json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print("West Beauty customization applied")
print(json.dumps(manifest,ensure_ascii=False,indent=2))
