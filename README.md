# [secc](https://github.com/ivere27/secc) bash shell frontend
a project of 'Second Compiler'.

## Key Features
- using bin utils for distributed compilation
- linux/mac cross compile(see SECC_CROSS in secc)

## How to use
```sh
git clone https://github.com/ivere27/secc-shell.git
```
edit SCHEDULER_HOST, SCHEDULER_PORT of secc.sh
```sh
vi secc-shell/secc.sh

#SCHEDULER_HOST="172.17.42.1"
#SCHEDULER_PORT="10509"
```
then, (or export PATH=/path/to/secc-shell/bin:$PATH)
```sh
# (optional) DEBUG=* SECC_LOG=secc.log \
/path/to/secc-shell/bin/clang -c test.c
```