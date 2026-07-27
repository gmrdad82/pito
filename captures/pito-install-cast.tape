Output out/pito-install-cast.gif
Output out/pito-install-cast.txt

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 2000
Set Padding 20
Set TypingSpeed 30ms
Set Theme "Dracula"

# SAFETY: fake bin PATH-shadowed + docker daemon unreachable, before anything
# else runs. ${CAST_DIR} is exported by capture.sh (a fresh mktemp sandbox,
# per run) — this tape never hardcodes a path, so it runs from any checkout.
Hide
Type "export PATH=$CAST_DIR/fakebin:$PATH"
Enter
Type "export DOCKER_HOST=tcp://127.0.0.1:1"
Enter
Type "cd $CAST_DIR && rm -rf ./pito-cli && clear"
Enter
Sleep 500ms
Show

Type "./install.sh --dir ./pito-cli"
Enter
Sleep 1200ms
Type "3"
Enter
Sleep 1200ms
Type "http://localhost:3028"
Enter
Sleep 2500ms
Type "n"
Enter
Sleep 1000ms
Type "n"
Enter
Sleep 1500ms
