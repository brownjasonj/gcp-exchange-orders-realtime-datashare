#include "crow.h"
#include <iostream>

struct CORSMiddleware {
    struct context {};
    void before_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        std::cout << "before_handle called for " << req.url << "\n";
    }
    void after_handle(crow::request& req, crow::response& res, context& /*ctx*/) {
        std::cout << "after_handle called for " << req.url << "\n";
        res.add_header("Access-Control-Allow-Origin", "*");
    }
};

int main() {
    crow::App<CORSMiddleware> app;
    CROW_ROUTE(app, "/api/config").methods(crow::HTTPMethod::POST)([](){ return "OK"; });
    app.port(18080).run();
}
