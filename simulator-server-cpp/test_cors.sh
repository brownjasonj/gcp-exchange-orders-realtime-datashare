mkdir -p build && cd build
cmake ..
make -j4
./simulator-server-cpp config.json &
PID=$!
sleep 2
curl -v -X OPTIONS http://localhost:8080/api/config
kill $PID
