Output out/pito-cli-cast.gif
Output out/pito-cli-cast.txt

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 2000
Set Padding 20
Set TypingSpeed 30ms
Set Theme "Dracula"

# SAFETY: fake bin PATH-shadowed + docker daemon unreachable, before anything
# else runs. ${CAST_DIR} is exported by capture.sh (a fresh mktemp sandbox,
# already installed into ${CAST_DIR}/pito-cli by the install cast) — this
# tape never hardcodes a path, so it runs from any checkout. Install dir also
# on PATH so `pito-cli` runs bare, from anywhere (mirrors the real
# linked-onto-PATH experience from the install cast).
Hide
Type "export PATH=$CAST_DIR/fakebin:$CAST_DIR/pito-cli:$PATH"
Enter
Type "export DOCKER_HOST=tcp://127.0.0.1:1"
Enter
Type "cd $CAST_DIR && clear"
Enter
Sleep 500ms
Show

Type "pito-cli --help"
Enter
Sleep 1500ms
Type "pito-cli version"
Enter
Sleep 1500ms
Type "pito-cli logs --tail 20"
Enter
Sleep 1500ms
Type "pito-cli up -d"
Enter
Sleep 2000ms
