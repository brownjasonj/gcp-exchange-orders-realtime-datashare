cmake_minimum_required(VERSION 3.10)
project(simulator-server-cpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# Nlohmann JSON
find_package(nlohmann_json REQUIRED)

# Drogon REST Framework (using git to ensure submodules like trantor are pulled)
FetchContent_Declare(
    drogon
    GIT_REPOSITORY https://github.com/drogonframework/drogon
    GIT_TAG v1.9.0
)
FetchContent_MakeAvailable(drogon)



# Google Cloud CPP - Found in the system (pre-installed in base image)
# Note: In this SDK version, bigquery_storage is bundled in the bigquery package
find_package(google_cloud_cpp_bigquery REQUIRED)

# Find Protobuf and gRPC
find_package(Protobuf REQUIRED)
find_package(gRPC REQUIRED)

# Protobuf generation
set(PROTO_SRC "src/pricing_message.proto")
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${PROTO_SRC})

add_executable(simulator-server-cpp
    src/main.cpp
    src/simulator.cpp
    src/bigquery_client.cpp
    ${PROTO_SRCS}
    ${PROTO_HDRS}
)

target_link_libraries(simulator-server-cpp
    PRIVATE
    nlohmann_json::nlohmann_json
    drogon
    google-cloud-cpp::bigquery
    protobuf::libprotobuf
    gRPC::grpc++
)

target_include_directories(simulator-server-cpp PRIVATE 
    src
    ${CMAKE_CURRENT_BINARY_DIR}
)
