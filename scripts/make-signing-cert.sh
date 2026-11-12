#!/bin/bash
# 在「登录」钥匙串里创建一个本机自用的代码签名证书「DockDot Local Signing」。
# 用它签名后，每次重新编译 DockDot 都不会丢失「辅助功能」权限。只需要运行一次。
set -euo pipefail

NAME="DockDot Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "证书「$NAME」已经存在，不用再建。"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > cert.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null
PW=$(openssl rand -hex 12)
# macOS 钥匙串只认旧的 PKCS#12 加密格式，所以显式指定 3DES/SHA1
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout "pass:$PW" -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P "$PW" -T /usr/bin/codesign >/dev/null

echo "已创建证书「$NAME」（显示为「不受信任」是正常的，不影响签名）。"
