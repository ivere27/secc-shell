# [secc](https://github.com/ivere27/secc) bash shell frontend
a project of 'Second Compiler'.

## Key Features
- using bin utils for distributed compilation
- linux/mac cross compile(see SECC_CROSS in secc)

## How to use
```sh
git clone https://github.com/ivere27/secc-shell.git
```
edit SECC_ADDRESS, SECC_PORT of secc.sh
```sh
vi secc-shell/secc.sh

#SECC_ADDRESS="172.17.42.1"
#SECC_PORT="10509"
```
then, (or export PATH=/path/to/secc-shell/bin:$PATH)
```sh
# (optional) DEBUG=* SECC_LOG=secc.log \
/path/to/secc-shell/bin/clang -c test.c
```

## CC/CXX example
```sh
NUMBER_OF_PROCESSORS=16 SECC_ADDRESS=172.17.42.1 SECC_CACHE=0 \
CC=/path/to/secc-shell/bin/gcc CXX=/path/to/secc-shell/bin/g++ ./build-webkit --gtk --release
```

## Test purposes
```sh
DEBUG=* SECC_ADDRESS=172.17.42.1 SECC_MODE=1 SECC_CACHE=0 /path/to/secc-shell/bin/gcc -c test.c
```

# License
MIT
