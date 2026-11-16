import io

p = 'Sources/Core/TerminalProfile.swift'
s = io.open(p, encoding='utf-8').read()

ids = {
    'Android 手机': '0A11D001-0000-4000-8000-000000000001',
    'Android 平板': '0A11D001-0000-4000-8000-000000000002',
    '小米手机': '0A11D001-0000-4000-8000-000000000003',
    '华为平板': '0A11D001-0000-4000-8000-000000000004',
}

for name, uid in ids.items():
    old = '        name: "%s",\n' % name
    new = '        id: UUID(uuidString: "%s")!,\n        name: "%s",\n' % (uid, name)
    if old not in s:
        raise SystemExit('missing: ' + name)
    s = s.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched 4 builtin profile ids')
