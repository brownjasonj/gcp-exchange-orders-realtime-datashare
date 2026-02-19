#include "crow.h"
#include "crow/middlewares/cors.h"
#include <iostream>

int main() {
    crow::App<crow::CORSHandler> app;
    app.loglevel(crow::LogLevel::Warning);
    
    auto& cors = app.get_middleware<crow::CORSHandler>();
    cors.global()
        .headers("Content-Type")
        .methods("GET"_method, "POST"_method, "OPTIONS"_method)
        .origin("*");

    CROW_ROUTE(app, "/api/test").methods("GET"_method, "OPTIONS"_method)([](){
        return "Hello World";
    });

    app.port(8081).multithreaded().run();
    return 0;
}
