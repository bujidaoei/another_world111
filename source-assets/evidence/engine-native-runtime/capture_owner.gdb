set pagination off
set confirm off
set print pretty on
set print elements 32
set breakpoint pending off
set logging file native-gdb.log
set logging overwrite on
set logging redirect off
set logging enabled on
source D:/bugu_projects/another_world/artifacts/engine-native-runtime/capture_owner.py
info breakpoints
run
info program
